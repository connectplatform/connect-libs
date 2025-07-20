# ConnectPlatform LibPhoneNumber - Modern Makefile
# Compatible with Erlang/OTP 26, CMake 4.0+, and C++17

.DEFAULT_GOAL := compile

REBAR=rebar3
DRIVER_REV ?= v8.13.27

# Modern NIF compilation with better error handling
nif_compile:
	@echo "🚀 Building ConnectPlatform LibPhoneNumber NIF..."
	@chmod +x build_deps_modern.sh
	@./build_deps_modern.sh $(DRIVER_REV)
	@$(MAKE) V=0 -C c_src -j$(shell nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
	@echo "✅ NIF compilation completed"

# Clean NIF artifacts
nif_clean:
	@echo "🧹 Cleaning NIF build artifacts..."
	@$(MAKE) -C c_src clean
	@rm -rf _build/deps priv
	@echo "✅ NIF cleanup completed"

# Compile Erlang code
compile: nif_compile
	@echo "📦 Compiling Erlang modules..."
	${REBAR} compile
	@echo "✅ Compilation completed"

# Clean everything
clean: nif_clean
	@echo "🧹 Cleaning all build artifacts..."
	${REBAR} clean
	@echo "✅ Cleanup completed"

# Test the library
test: compile
	@echo "🧪 Running tests..."
	${REBAR} eunit
	${REBAR} ct
	@echo "✅ Tests completed"

# Check code quality
check:
	@echo "🔍 Running code quality checks..."
	${REBAR} dialyzer
	${REBAR} xref
	@echo "✅ Code quality checks completed"

# Quick development build (skip tests)
dev: compile
	@echo "🚀 Development build ready"

# Full release build with all checks
release: clean compile test check
	@echo "🎉 Release build completed successfully!"

# Show build information
info:
	@echo "ConnectPlatform LibPhoneNumber Build Information"
	@echo "=============================================="
	@echo "Rebar3: $(shell ${REBAR} --version)"
	@echo "Erlang: $(shell erl -version 2>&1)"
	@echo "OS: $(shell uname -s)"
	@echo "Architecture: $(shell uname -m)"
	@echo "CMake: $(shell cmake --version | head -1)"
	@echo "C++ Compiler: $(shell $(CXX) --version | head -1 2>/dev/null || echo 'Not found')"
	@echo "Driver Revision: $(DRIVER_REV)"

# Help target
help:
	@echo "ConnectPlatform LibPhoneNumber - Available Targets"
	@echo "================================================"
	@echo "compile     - Build the library (default)"
	@echo "clean       - Clean all build artifacts"
	@echo "test        - Run all tests"
	@echo "check       - Run code quality checks"
	@echo "dev         - Quick development build"
	@echo "release     - Full release build with all checks"
	@echo "info        - Show build environment information"
	@echo "help        - Show this help message"
	@echo ""
	@echo "NIF-specific targets:"
	@echo "nif_compile - Build only the NIF components"
	@echo "nif_clean   - Clean only NIF artifacts"

.PHONY: compile clean test check dev release info help nif_compile nif_clean
