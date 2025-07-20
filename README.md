# ConnectPlatform Libraries

> **Modernized, secure, and performant libraries for ConnectPlatform v8**

This repository contains all modernized dependencies for ConnectPlatform, rewritten and optimized for:
- **Erlang/OTP 26+** compatibility
- **Modern C++17** standards  
- **CMake 4.0+** build systems
- **Enhanced security** and performance
- **ConnectPlatform v8** multi-transport architecture

## 📚 **Available Libraries**

### **🔢 libphonenumber**
Modern phone number validation and formatting library.
- **Status**: ✅ **Production Ready**
- **Replaces**: `elibphonenumber` (legacy)
- **Features**: 
  - Google libphonenumber v8.13.27 integration
  - Erlang/OTP 26 compatible
  - CMake 4.0+ build system
  - C++17 standards
  - Comprehensive phone validation and formatting

**Usage in rebar.config:**
```erlang
{deps, [
  {connect_libphonenumber, {git, "https://github.com/connectplatform/connect-libs.git", 
                          {dir, "libphonenumber"}, {branch, "main"}}}
]}.
```

### **🔄 Coming Soon**

#### **mongodb** (Phase 2)
Modern MongoDB driver for ConnectPlatform.
- **Status**: 🔄 **Planned**
- **Replaces**: `cocktail_mongo` (legacy)

#### **json** (Phase 2)  
High-performance JSON processing.
- **Status**: 🔄 **Planned**
- **Replaces**: `yaws_json2` (legacy)

#### **magic** (Phase 2)
File type detection and MIME handling.
- **Status**: 🔄 **Planned**
- **Replaces**: `emagic` (legacy)

#### **search** (Phase 3)
Modern Elasticsearch client.
- **Status**: 🔄 **Planned**
- **Replaces**: `erlastic_search` (legacy)

#### **http** (Phase 3)
Modern HTTP client and server utilities.
- **Status**: 🔄 **Planned**
- **Replaces**: `smoothie` (legacy)

---

## 🚀 **Quick Start**

### **1. Add to your rebar.config**
```erlang
{minimum_otp_vsn, "26"}.

{deps, [
  % ConnectPlatform modernized libraries
  {connect_libphonenumber, {git, "https://github.com/connectplatform/connect-libs.git",
                          {dir, "libphonenumber"}, {branch, "main"}}}
]}.
```

### **2. Build your project**
```bash
export PATH="/usr/local/opt/erlang@26/bin:$PATH"
rebar3 get-deps
rebar3 compile
```

### **3. Use in your Erlang code**
```erlang
%% Phone number validation example
{ok, PhoneNumber} = phonenumber_util:parse(<<"+1234567890">>, <<"US">>),
IsValid = phonenumber_util:is_valid_number(PhoneNumber).
```

---

## 🔧 **Development**

### **Prerequisites**
- **Erlang/OTP 26+**
- **rebar3 3.22+**
- **CMake 4.0+** (for native libraries)
- **Modern C++17 compiler**

### **Building Individual Libraries**
```bash
# Build libphonenumber
cd libphonenumber
make compile

# Run tests
make test

# Clean build
make clean
```

### **Adding New Libraries**
1. Create subdirectory: `mkdir new-library`
2. Follow ConnectPlatform standards:
   - Erlang/OTP 26+ compatibility
   - Modern build system (rebar3, CMake 4.0+)
   - Comprehensive tests
   - Security best practices
3. Update this README
4. Submit pull request

---

## 🌟 **Key Improvements**

### **vs Legacy Dependencies**
| Feature | Legacy | ConnectPlatform Libraries |
|---------|---------|--------------------------|
| **Erlang Version** | 13.x-25.x | **26+** |
| **Build System** | Mixed/Outdated | **Standardized Modern** |
| **C++ Standard** | C++11/14 | **C++17** |
| **CMake** | 2.x/3.x | **4.0+** |
| **Security** | Outdated | **Latest Patches** |
| **Maintenance** | Abandoned | **Active Development** |
| **Performance** | Legacy | **Optimized** |
| **Testing** | Minimal | **Comprehensive** |

### **ConnectPlatform v8 Integration**
- **Multi-transport aware**: Internet, HF/VHF Radio, Bluetooth 5 Mesh
- **Enhanced error handling** for unreliable transport conditions  
- **Performance optimized** for tactical communication scenarios
- **Security hardened** for sensitive communications

---

## 📋 **Roadmap**

### **Phase 1** (Current)
- ✅ **libphonenumber** - Phone validation/formatting
- ✅ **Modern build infrastructure**
- ✅ **Erlang/OTP 26 compatibility**

### **Phase 2** (Next)
- 🔄 **mongodb** - Database connectivity
- 🔄 **json** - JSON processing  
- 🔄 **magic** - File type detection

### **Phase 3** (Future)
- 🔄 **search** - Elasticsearch client
- 🔄 **http** - HTTP client/server
- 🔄 **crypto** - Enhanced cryptography
- 🔄 **compression** - Data compression utilities

---

## 🤝 **Contributing**

1. **Fork** the repository
2. **Create feature branch**: `git checkout -b feature/new-library`
3. **Follow standards**: Erlang/OTP 26+, modern build systems
4. **Add tests**: Comprehensive test coverage required
5. **Update docs**: README and inline documentation  
6. **Submit PR**: Detailed description of changes

### **Code Standards**
- **Erlang**: OTP 26+ with modern practices
- **C++**: C++17 standard, memory-safe patterns
- **Build**: CMake 4.0+, rebar3 3.22+
- **Tests**: EUnit, Common Test, PropEr
- **Docs**: ExDoc, comprehensive READMEs

---

## 📄 **License**

Individual libraries maintain their original licenses where applicable.
ConnectPlatform-specific code and modifications are licensed under MIT.

---

## 🔗 **Links**

- **ConnectPlatform**: [github.com/connectplatform](https://github.com/connectplatform)  
- **Documentation**: [docs.connectplatform.dev](https://docs.connectplatform.dev)
- **Issues**: [GitHub Issues](https://github.com/connectplatform/connect-libs/issues)
- **Discussions**: [GitHub Discussions](https://github.com/connectplatform/connect-libs/discussions)

---

**ConnectPlatform v8 - Revolutionizing Multi-Transport Communication** 🚀 