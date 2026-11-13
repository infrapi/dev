package main

import (
	"net/http"
	"sort"
	"sync"
	"time"

	"github.com/gin-gonic/gin"

	"github.com/infrapi/lib/pkg/api"
	infraerrors "github.com/infrapi/lib/pkg/errors"
	"github.com/infrapi/lib/pkg/server"
)

// VM is the API's one resource.
type VM struct {
	Name      string    `json:"name"`
	CPUs      int       `json:"cpus"`
	MemoryMB  int       `json:"memory_mb"`
	CreatedAt time.Time `json:"created_at"`
}

// store keeps the VMs of every namespace, in memory: they go with the
// process.
type store struct {
	mu  sync.Mutex
	vms map[string]map[string]VM // namespace -> name -> VM
}

func newStore() *store { return &store{vms: map[string]map[string]VM{}} }

// register mounts the vms resource on the API group: list, create, get,
// delete. Kayra learns it from the specification infrapi/lib generates
// from these routes, at /-/openapi.json.
func register(r gin.IRouter, s *store) {
	r.GET("/vms", s.list)
	r.POST("/vms", s.create)
	r.GET("/vms/:name", s.get)
	r.DELETE("/vms/:name", s.delete)
}

func (s *store) list(c *gin.Context) {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := []VM{}
	for _, vm := range s.vms[server.Namespace(c)] {
		out = append(out, vm)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Name < out[j].Name })
	c.JSON(http.StatusOK, out)
}

func (s *store) create(c *gin.Context) {
	var vm VM
	if err := c.ShouldBindJSON(&vm); err != nil {
		server.AbortError(c, infraerrors.Invalid("vm: %s", err))
		return
	}
	// a name is one path segment: the same rule as a namespace's
	if err := api.ValidateNamespace(vm.Name); err != nil {
		server.AbortError(c, infraerrors.Invalid("vm name %q: a lower case DNS label, like web-1", vm.Name))
		return
	}
	if vm.CPUs <= 0 {
		vm.CPUs = 1
	}
	if vm.MemoryMB <= 0 {
		vm.MemoryMB = 1024
	}
	ns := server.Namespace(c)
	s.mu.Lock()
	defer s.mu.Unlock()
	if current, ok := s.vms[ns][vm.Name]; ok {
		server.AbortError(c, infraerrors.AlreadyExists(current, "vm %q already exists in namespace %q", vm.Name, ns))
		return
	}
	if s.vms[ns] == nil {
		s.vms[ns] = map[string]VM{}
	}
	vm.CreatedAt = time.Now().UTC()
	s.vms[ns][vm.Name] = vm
	c.JSON(http.StatusCreated, vm)
}

func (s *store) get(c *gin.Context) {
	s.mu.Lock()
	defer s.mu.Unlock()
	vm, ok := s.vms[server.Namespace(c)][c.Param("name")]
	if !ok {
		server.AbortError(c, infraerrors.NotFound("vm %q not found in namespace %q", c.Param("name"), server.Namespace(c)))
		return
	}
	c.JSON(http.StatusOK, vm)
}

func (s *store) delete(c *gin.Context) {
	ns, name := server.Namespace(c), c.Param("name")
	s.mu.Lock()
	defer s.mu.Unlock()
	if _, ok := s.vms[ns][name]; !ok {
		server.AbortError(c, infraerrors.NotFound("vm %q not found in namespace %q", name, ns))
		return
	}
	delete(s.vms[ns], name)
	c.Status(http.StatusNoContent)
}
