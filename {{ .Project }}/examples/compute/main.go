// Command compute is the InfraPI dev stack's example API: virtual machines,
// kept in memory, served under /apis/<group>/v1/namespaces/<ns>/vms with
// infrapi/lib, every request authenticated and authorized by Kayra.
//
// Settings come from the dotenv file named by INFRAPI_CONFIG_DOTENV_FILE
// (.env by default; make example renders one from dev.yaml): the
// INFRAPI_APP_* keys of infrapi/lib, COMPUTE_API_GROUP, the API group
// (compute.infrapi.io unless set), and COMPUTE_AUTH_URL, Kayra's URL. See
// docs/create-an-api.md.
package main

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/infrapi/lib/pkg/api"
	"github.com/infrapi/lib/pkg/auth"
	"github.com/infrapi/lib/pkg/config"
	"github.com/infrapi/lib/pkg/listener"
	"github.com/infrapi/lib/pkg/logger"
	"github.com/infrapi/lib/pkg/server"
)

// defaultGroup is this API's group, named in full, unless COMPUTE_API_GROUP
// says otherwise: the name it is registered under in Kayra.
const defaultGroup = "compute.infrapi.io"

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	if err := run(ctx); err != nil {
		fmt.Fprintln(os.Stderr, "compute:", err)
		os.Exit(1)
	}
}

func run(ctx context.Context) error {
	vars, err := config.NewConfig()
	if err != nil {
		return err
	}
	app, err := vars.GetAppConfig()
	if err != nil {
		return err
	}
	authURL, err := vars.GetString(&config.VariableOpts{Key: "COMPUTE_AUTH_URL", Validator: "url"})
	if err != nil {
		return err
	}
	name, err := vars.GetString(&config.VariableOpts{Key: "COMPUTE_API_GROUP", Default: defaultGroup})
	if err != nil {
		return err
	}
	// /apis/<group>/v1: the API, and infrapi/lib's own endpoints under -/
	group := api.Group{Name: name, Version: "v1"}
	if err := group.Validate(); err != nil {
		return fmt.Errorf("COMPUTE_API_GROUP: %w", err)
	}

	log, err := logger.New(logger.Options{Level: app.AppLogLevel.String(), Format: app.AppLogFormat, Name: "compute"})
	if err != nil {
		return err
	}
	logger.SetDefault(log)
	defer func() { _ = logger.Sync() }()

	// Kayra answers both questions: who the caller is (/oauth2/userinfo,
	// cached), and whether they may act (its check endpoint, on every
	// request). Its URL is all there is to configure: the rest is in its
	// /.well-known/kayra.json.
	kayra, err := auth.NewClient(auth.ClientOptions{BaseURL: authURL})
	if err != nil {
		return err
	}
	engine, err := server.NewServerGin(app, []string{group.Root()}, server.WithAuth(kayra.Middleware()))
	if err != nil {
		return err
	}
	routes, err := server.APIGroup(engine, group)
	if err != nil {
		return err
	}
	routes.Use(kayra.RequireAccess())
	register(routes, newStore())

	ln, err := listener.Listen(app)
	if err != nil {
		return err
	}
	srv := &http.Server{Handler: engine, ReadHeaderTimeout: 10 * time.Second}
	served := make(chan error, 1)
	go func() { served <- srv.Serve(ln) }()
	log.Info("serving", logger.String("address", ln.Addr().String()), logger.String("api", group.Root()),
		logger.String("auth", authURL))

	select {
	case err := <-served:
		return err
	case <-ctx.Done():
	}
	shutdown, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := srv.Shutdown(shutdown); err != nil && !errors.Is(err, http.ErrServerClosed) {
		return err
	}
	return nil
}
