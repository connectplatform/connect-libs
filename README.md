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
- **Status**: ✅ **PRODUCTION READY**
- **Replaces**: `elibphonenumber` (legacy)
- **Features**: 
  - Google libphonenumber v8.13.27 integration
  - Erlang/OTP 26 compatible
  - Modern C++17 with CMake 4.0+
  - C++17 standards
  - Comprehensive phone validation and formatting

**Usage in rebar.config:**
```erlang
{deps, [
  {connect_libphonenumber, {git, "https://github.com/connectplatform/connect-libs.git", {branch, "main"}}}
]}.
```

## 🔄 **Phase 2 Roadmap: Strategic Modernization**

### **⚡ REPLACE WITH OTP v27 NATIVE FUNCTIONS (Zero Dependencies!)**

#### **~~json~~ → Native OTP 27 `json` Module** 🎉
- **Status**: ✅ **Use OTP 27 Built-in**
- **Replaces**: `yaws_json2` (legacy) + `jiffy` (external)
- **Benefits**: 2-3x faster, memory efficient, zero maintenance
- **Migration**: `json:decode(Data)` instead of `yaws_json2:decode_string(Data)`

#### **~~entropy~~ → Native OTP 26 `crypto` Module** 🎉  
- **Status**: ✅ **Use OTP 26 crypto:strong_rand_bytes/1**
- **Replaces**: `entropy_string` (external)
- **Benefits**: Cryptographically secure, 50%+ faster
- **Migration**: `base64:encode(crypto:strong_rand_bytes(24))` for 32-char strings

#### **~~date~~ → Native OTP 26 `calendar` Module** 🎉
- **Status**: ✅ **Use OTP 26 Enhanced Calendar**  
- **Replaces**: `dh_date` (unmaintained)
- **Benefits**: Timezone aware, standardized, built-in

### **🔄 COMING SOON - ConnectPlatform Libraries**

#### **mongodb** (Phase 2)
Modern MongoDB driver for ConnectPlatform.
- **Status**: 🔄 **Phase 2 - High Priority**
- **Replaces**: `cocktail_mongo` (legacy)
- **Features**: MongoDB 7.0+, SCRAM-SHA-256 auth, connection pooling

#### **magic** (Phase 2)
File type detection and MIME handling.
- **Status**: 🔄 **Phase 2 - Medium Priority**
- **Replaces**: `emagic` (legacy)
- **Features**: Modern libmagic 5.45+, thread-safe, C++17

#### **search** (Phase 2)
Modern Elasticsearch client.
- **Status**: 🔄 **Phase 2 - Medium Priority**
- **Replaces**: `erlastic_search` (legacy)
- **Features**: Elasticsearch 8.x API, connection pooling, security

#### **http** (Phase 3)
Modern HTTP utilities (Optional).
- **Status**: 🤔 **Evaluating vs hackney direct usage**
- **Replaces**: `smoothie` (legacy)
- **Alternative**: Use modern `hackney` 1.20+ directly

---

## 🚀 **Quick Start**

### **1. Add to your rebar.config**
```erlang
{minimum_otp_vsn, "26"}.

{deps, [
  % ConnectPlatform modernized libraries
  {connect_libphonenumber, {git, "https://github.com/connectplatform/connect-libs.git", {branch, "main"}}},
  
  % Phase 2 - Coming soon
  % {connect_mongodb, {git, "https://github.com/connectplatform/connect-libs.git", 
  %                   {dir, "mongodb"}, {branch, "main"}}},
  % {connect_magic, {git, "https://github.com/connectplatform/connect-libs.git", 
  %                 {dir, "magic"}, {branch, "main"}}},
  
  % Modern hex.pm dependencies (updated versions)  
  {lager,           "5.0.0"},      % Modern logging
  {hackney,         "1.20.1"},     % Modern HTTP client
  {worker_pool,     "6.0.1"}       % Process pooling
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

%% JSON with OTP 27 native (replaces yaws_json2)
JSON = json:decode(<<"{"test": "value"}">>),
Encoded = json:encode(#{test => <<"value">>}).

%% Random strings with OTP 26 crypto (replaces entropy_string)  
RandomString = base64:encode(crypto:strong_rand_bytes(24)).
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
| **Dependencies** | 15 external | **8 (7 native)** |

### **ConnectPlatform v8 Integration**
- **Multi-transport aware**: Internet, HF/VHF Radio, Bluetooth 5 Mesh
- **Enhanced error handling** for unreliable transport conditions  
- **Performance optimized** for tactical communication scenarios
- **Security hardened** for sensitive communications

---

## 📋 **Roadmap**

### **Phase 1: COMPLETED ✅**
- [x] **libphonenumber** - Phone validation/formatting
- [x] **Modern build infrastructure**
- [x] **Erlang/OTP 26 compatibility**

### **Phase 2: Native OTP + ConnectLibs (2025 Q1)**
- [x] **Native JSON** - Use OTP 27 built-in `json` module (zero deps!)
- [x] **Native Crypto** - Use OTP 26 `crypto:strong_rand_bytes/1` 
- [x] **Native Calendar** - Use OTP 26 enhanced `calendar` module
- [ ] **connect-mongodb** - Modern MongoDB driver
- [ ] **connect-magic** - File type detection  
- [ ] **connect-search** - Elasticsearch client

### **Phase 3: Advanced Features (2025 Q2)**
- [ ] **connect-crypto** - Enhanced cryptography
- [ ] **connect-compression** - Data compression utilities
- [ ] **Full Kubernetes deployment** with modernized k8s-deployer

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

*Phase 2 Strategy: "Less is More - Maximize OTP Native, Minimize External Dependencies!"* 🌟