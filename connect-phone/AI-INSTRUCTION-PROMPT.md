# 🤖 AI Instruction Prompt: Connect-Phone Library

*Comprehensive knowledge base for AI coders working with the Connect-Phone pure Erlang library*

---

## 📋 **LIBRARY OVERVIEW**

**Connect-Phone** is a **pure Erlang OTP 27+ library** for phone number validation and normalization, specifically designed for using phone numbers as account identifiers. **Zero external dependencies**.

### **Core Purpose**
- Normalize phone numbers to consistent E164 format for account IDs
- Validate international phone numbers for user registration/authentication
- Ensure same user always gets same account ID regardless of input formatting
- Reject incomplete/invalid numbers for security

### **Key Characteristics**
- ✅ **Pure Erlang**: No NIFs, no C++ dependencies
- ✅ **OTP 27+ Ready**: Native json module, enhanced error handling
- ✅ **Type Safe**: 2 Dialyzer warnings, precise specs
- ✅ **Account ID Focused**: Specifically designed for user identification
- ✅ **International Format Required**: Requires +CC format for safety

---

## 🔧 **COMPLETE API REFERENCE**

### **Core Functions**

#### `normalize_account_id/1`
```erlang
-spec normalize_account_id(phone_number()) -> validation_result().
% Primary function for account ID normalization
% Input: Any phone number format  
% Output: {ok, E164Binary} | {error, Reason}
% Example: normalize_account_id(<<"+1-555-123-4567">>) -> {ok, <<"+15551234567">>}
```

#### `validate_account_id/1`
```erlang
-spec validate_account_id(binary()) -> validation_result().  
% Same as normalize_account_id/1 but clearer name for validation context
% Identical functionality and output
```

#### `is_valid/1`
```erlang
-spec is_valid(term()) -> boolean().
% Quick boolean validation check
% Example: is_valid(<<"+15551234567">>) -> true
```

#### `get_phone_info/1`
```erlang
-spec get_phone_info(term()) -> phone_info() | {error, invalid_input | phone_info_failed}.
% Returns detailed phone information including country metadata
% Output map includes: phone, valid, country_metadata, errors
```

#### `format_e164/1`
```erlang
-spec format_e164(term()) -> {ok, nonempty_binary()} | {error, atom()}.
% Format to E164 (alias for normalize_account_id/1)
```

#### `extract_country_info/1`
```erlang
-spec extract_country_info(term()) -> {ok, country_info()} | {error, atom()}.
% Extract country code, ID, and name from phone number
% Returns: #{code => Binary, id => CountryID, name => CountryName}
```

### **OTP 27 Enhanced Functions**

#### `get_phone_info_json/1`
```erlang
-spec get_phone_info_json(term()) -> iodata() | {error, atom()}.
% JSON-encoded phone info using OTP 27 native json module
% Enhanced error handling with error_info maps
```

#### `validate_with_enhanced_errors/1`
```erlang
-spec validate_with_enhanced_errors(term()) -> validation_result().
% Enhanced validation with detailed OTP 27 error context
% Includes stacktraces, error_info maps, input type information
```

#### `batch_validate/1`
```erlang
-spec batch_validate([term()]) -> [{term(), validation_result()}].
% Efficiently validate multiple phone numbers
% Returns list of {Input, ValidationResult} tuples
```

---

## 📊 **TYPE DEFINITIONS**

```erlang
-type phone_number() :: binary().
-type account_id() :: nonempty_binary().
-type validation_result() :: {ok, account_id()} | {error, atom()}.

-type phone_info() :: #{
    phone := binary(),
    valid := boolean(),
    country_metadata => #{
        code := binary(),
        id := <<_:16,_:_*40>>,      % Precise binary size for country ID
        name := <<_:40,_:_*8>>      % Precise binary size for country name
    },
    errors => [error_atom()]        % Specific error types, not generic term()
}.

% Error atom types:
% invalid_country_code_length | invalid_format | invalid_length_for_country |
% invalid_national_number | national_number_too_long | national_number_too_short |
% non_numeric_country_code | non_numeric_national_number | requires_country_code
```

---

## ⚠️ **CRITICAL ERROR TYPES & USER MESSAGES**

| **Error Atom** | **Meaning** | **User-Friendly Message** |
|----------------|-------------|---------------------------|
| `requires_country_code` | Missing country code | "Please include country code (e.g., +1)" |
| `invalid_format` | Malformed number | "Please enter a valid phone number" |
| `national_number_too_short` | Incomplete national part | "Phone number appears incomplete" |
| `national_number_too_long` | National part too long | "Phone number too long" |
| `non_numeric_national_number` | Contains letters/symbols | "Phone number should contain only digits" |
| `invalid_country_code_length` | Country code wrong length | "Invalid country code length" |
| `invalid_length_for_country` | Wrong length for country | "Invalid number length for this country" |
| `unknown_country_code` | Unsupported country | "Country code not recognized" |
| `invalid_input` | Wrong input type | "Invalid input format" |

---

## 🎯 **USAGE PATTERNS & BEST PRACTICES**

### **User Registration Flow**
```erlang
register_user(PhoneInput, UserData) ->
    case connect_phone:normalize_account_id(PhoneInput) of
        {ok, AccountId} ->
            % Use AccountId as primary key
            create_user_account(AccountId, UserData);
        {error, Reason} ->
            {error, format_phone_error(Reason)}
    end.
```

### **Authentication Flow**
```erlang
authenticate_user(PhoneInput) ->
    case connect_phone:normalize_account_id(PhoneInput) of
        {ok, AccountId} ->
            find_user_by_account_id(AccountId);
        {error, _} ->
            {error, invalid_phone}
    end.
```

### **Batch Processing**
```erlang
validate_user_list(PhoneNumbers) ->
    Results = connect_phone:batch_validate(PhoneNumbers),
    lists:filtermap(fun({Phone, {ok, AccountId}}) -> 
        {true, {Phone, AccountId}};
    ({_Phone, {error, _}}) -> 
        false 
    end, Results).
```

### **JSON API Integration (OTP 27)**
```erlang
handle_phone_info(PhoneNumber) ->
    case connect_phone:get_phone_info_json(PhoneNumber) of
        JsonData when is_binary(JsonData); is_list(JsonData) ->
            {ok, JsonData};
        {error, Reason} ->
            {error, #{error => Reason, message => <<"Invalid phone number">>}}
    end.
```

---

## 🌍 **INTERNATIONAL SUPPORT (25+ Countries)**

**Supported Country Codes:**
```erlang
% Major supported countries with precise validation rules:
"1"   -> US/Canada     | "44"  -> UK           | "49"  -> Germany
"33"  -> France        | "39"  -> Italy        | "34"  -> Spain  
"31"  -> Netherlands   | "41"  -> Switzerland  | "43"  -> Austria
"32"  -> Belgium       | "45"  -> Denmark      | "46"  -> Sweden
"47"  -> Norway        | "358" -> Finland      | "48"  -> Poland
"420" -> Czech Rep     | "421" -> Slovakia     | "36"  -> Hungary
"40"  -> Romania       | "359" -> Bulgaria     | "385" -> Croatia
"386" -> Slovenia      | "370" -> Lithuania    | "371" -> Latvia
"372" -> Estonia       | "380" -> Ukraine      | "7"   -> Russia
"81"  -> Japan         | "82"  -> South Korea  | "86"  -> China
"91"  -> India         | "61"  -> Australia    | "64"  -> New Zealand
"55"  -> Brazil        | "52"  -> Mexico       | "54"  -> Argentina
% ... and more
```

---

## 🚨 **STRICT DESIGN RULES**

### **1. International Format Required**
```erlang
% ✅ ACCEPTED - Unambiguous
{ok, _} = connect_phone:normalize_account_id(<<"+15551234567">>).

% ❌ REJECTED - Ambiguous without country code  
{error, requires_country_code} = connect_phone:normalize_account_id(<<"5551234567">>).
```

### **2. Input Normalization**
```erlang
% All these produce the same account ID:
Inputs = [
    <<"+1-555-123-4567">>,
    <<"+1 555 123 4567">>,  
    <<"+1.555.123.4567">>,
    <<"+1(555)123-4567">>,
    <<"+15551234567">>
],
Expected = {ok, <<"+15551234567">>},
[Expected = connect_phone:normalize_account_id(Input) || Input <- Inputs].
```

### **3. Malformed Input Rejection**
```erlang
% These are intentionally rejected for safety:
{error, invalid_format} = connect_phone:normalize_account_id(<<"+-15551234567">>).
{error, invalid_format} = connect_phone:normalize_account_id(<<"++15551234567">>).
{error, invalid_format} = connect_phone:normalize_account_id(<<"123">>).
```

---

## 🛡️ **SECURITY & RELIABILITY GUIDELINES**

### **Account Enumeration Prevention**
```erlang
% Always normalize before storing to prevent enumeration:
% Different formats of same number -> same account ID
```

### **Input Validation**
```erlang
% Validate input type before processing:
validate_phone_input(Input) when is_binary(Input) ->
    connect_phone:normalize_account_id(Input);
validate_phone_input(_) ->
    {error, invalid_input}.
```

### **Error Handling Pattern**
```erlang
handle_phone_validation(PhoneInput) ->
    try 
        connect_phone:validate_with_enhanced_errors(PhoneInput)
    catch
        error:{phone_validation_error, _Reason} = Error ->
            % Enhanced error with stacktrace and context
            {error, Error};
        error:Other ->
            {error, {unexpected_error, Other}}
    end.
```

---

## ⚡ **PERFORMANCE CHARACTERISTICS**

- **Memory**: Low overhead, binary pattern matching
- **Latency**: Predictable, no external calls
- **Throughput**: High, efficient Erlang binary operations  
- **Startup**: Zero - no external dependencies to initialize
- **Type Safety**: Dialyzer-optimized (88% warning reduction)
- **Batch Processing**: Efficient list operations for multiple validations

---

## 🔧 **DEVELOPMENT & TESTING**

### **Build Requirements**
- Erlang/OTP 27+  
- Rebar3
- No external dependencies

### **Test Coverage**
- 19 comprehensive tests (100% pass rate)
- Account ID normalization scenarios
- Cross-format consistency validation  
- International number handling
- Error case coverage
- OTP 27 enhanced functions testing

### **Dialyzer Integration**
```bash
rebar3 dialyzer  # Should show minimal warnings
```

---

## 💡 **AI CODING GUIDELINES**

### **When to Use This Library**
- ✅ User registration/authentication systems
- ✅ Account management with phone as primary ID
- ✅ Multi-tenant applications needing consistent phone handling
- ✅ JSON APIs requiring phone validation
- ✅ Systems requiring batch phone processing

### **Integration Pattern**
```erlang
% Always pattern match on results:
case connect_phone:normalize_account_id(Input) of
    {ok, AccountId} -> 
        proceed_with_business_logic(AccountId);
    {error, Reason} ->
        handle_validation_error(Reason, Input)
end.
```

### **Error Handling Strategy**
```erlang
% Map internal errors to user-friendly messages:
format_phone_error(requires_country_code) -> 
    <<"Please include country code (e.g., +1 555-123-4567)">>;
format_phone_error(invalid_format) -> 
    <<"Please enter a valid phone number">>;
format_phone_error(national_number_too_short) ->
    <<"Phone number appears incomplete">>;
format_phone_error(_) -> 
    <<"Phone number format not recognized">>.
```

---

## 📦 **DEPENDENCY & BUILD INFO**

```erlang
% rebar.config
{minimum_otp_vsn, "27"}.
{deps, []}.  % Zero dependencies!

% No NIFs, no external libs, no compilation complexity
% Pure Erlang implementation
```

---

*This library is production-ready, type-safe, and specifically optimized for using phone numbers as account identifiers in modern Erlang/OTP applications.* 