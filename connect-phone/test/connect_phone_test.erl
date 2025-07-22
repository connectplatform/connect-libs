%%%-------------------------------------------------------------------
%%% @doc Connect Platform Phone Number Tests
%%%
%%% Comprehensive tests for phone number validation and normalization,
%%% with focus on account ID use cases.
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(connect_phone_test).

-include_lib("eunit/include/eunit.hrl").

%%%===================================================================
%%% Test Setup
%%%===================================================================

setup() ->
    % No external dependencies needed - pure Erlang implementation
    ok.

cleanup(_) ->
    ok.

%%%===================================================================
%%% Account ID Normalization Tests
%%%===================================================================

normalize_account_id_test_() ->
    {setup, fun setup/0, fun cleanup/1, [
        {"US phone number normalization", fun test_us_normalization/0},
        {"International phone number normalization", fun test_international_normalization/0},
        {"Invalid phone number handling", fun test_invalid_normalization/0},
        {"Incomplete phone number detection", fun test_incomplete_normalization/0},
        {"Formatted input handling", fun test_formatted_input/0}
    ]}.

test_us_normalization() ->
    % Standard US numbers - need full international format for libphonenumber_erlang
    ?assertEqual({ok, <<"+15551234567">>}, 
                connect_phone:normalize_account_id(<<"+15551234567">>)),
    ?assertEqual({ok, <<"+15551234567">>}, 
                connect_phone:normalize_account_id(<<"+1-555-123-4567">>)),
    ?assertEqual({ok, <<"+15551234567">>}, 
                connect_phone:normalize_account_id(<<"+1 555 123 4567">>)),
    
    % Already in E164 format
    ?assertEqual({ok, <<"+15551234567">>}, 
                connect_phone:normalize_account_id(<<"+15551234567">>)).

test_international_normalization() ->
    % UK numbers - must be in international format
    ?assertEqual({ok, <<"+447700900123">>}, 
                connect_phone:normalize_account_id(<<"+44 7700 900123">>)),
    
    % German numbers - must be in international format
    ?assertEqual({ok, <<"+4915123456789">>}, 
                connect_phone:normalize_account_id(<<"+49 151 23456789">>)).

test_invalid_normalization() ->
    % Too short
    ?assertMatch({error, _}, connect_phone:normalize_account_id(<<"123">>)),
    
    % Invalid format
    ?assertMatch({error, _}, connect_phone:normalize_account_id(<<"abc-def-ghij">>)),
    
    % Empty input
    ?assertMatch({error, _}, connect_phone:normalize_account_id(<<>>)),
    
    % Invalid number
    ?assertMatch({error, _}, connect_phone:normalize_account_id(<<"+1234">>)).

test_incomplete_normalization() ->
    % Numbers that are too short
    ?assertMatch({error, _}, 
                connect_phone:normalize_account_id(<<"+1555123">>)),
    
    % Missing digits
    ?assertMatch({error, _}, 
                connect_phone:normalize_account_id(<<"+11234567">>)).

test_formatted_input() ->
    % Various formatting styles should normalize to same result
    Inputs = [
        <<"+1-555-123-4567">>,
        <<"+1 555 123 4567">>,
        <<"+1.555.123.4567">>,
        <<"+1 (555) 123-4567">>,
        <<"+15551234567">>
    ],
    
    Expected = {ok, <<"+15551234567">>},
    [?assertEqual(Expected, connect_phone:normalize_account_id(Input)) 
     || Input <- Inputs].

%%%===================================================================
%%% Validation Tests
%%%===================================================================

validation_test_() ->
    {setup, fun setup/0, fun cleanup/1, [
        {"Basic validation", fun test_basic_validation/0},
        {"Regional validation", fun test_regional_validation/0},
        {"Edge case validation", fun test_edge_case_validation/0}
    ]}.

test_basic_validation() ->
    % Valid numbers - require international format
    ?assert(connect_phone:is_valid(<<"+15551234567">>)),
    ?assert(connect_phone:is_valid(<<"+447700900123">>)),
    
    % Invalid numbers
    ?assertNot(connect_phone:is_valid(<<"123">>)),
    ?assertNot(connect_phone:is_valid(<<"abc">>)),
    ?assertNot(connect_phone:is_valid(<<>>)).

test_regional_validation() ->
    % International numbers are validated regardless of format
    ?assert(connect_phone:is_valid(<<"+447700900123">>)),
    ?assert(connect_phone:is_valid(<<"+15551234567">>)),
    
    % Domestic format doesn't work without country context
    ?assertNot(connect_phone:is_valid(<<"5551234567">>)),
    ?assertNot(connect_phone:is_valid(<<"07700900123">>)).

test_edge_case_validation() ->
    % Non-binary input
    ?assertNot(connect_phone:is_valid("5551234567")),
    ?assertNot(connect_phone:is_valid(5551234567)),
    
    % Non-string input
    ?assertNot(connect_phone:is_valid(undefined)),
    ?assertNot(connect_phone:is_valid(["+15551234567"])).

%%%===================================================================
%%% Formatting Tests
%%%===================================================================

formatting_test_() ->
    {setup, fun setup/0, fun cleanup/1, [
        {"E164 formatting", fun test_e164_formatting/0},
        {"Phone info extraction", fun test_phone_info/0}
    ]}.

test_e164_formatting() ->
    ?assertEqual({ok, <<"+15551234567">>}, 
                connect_phone:format_e164(<<"+1-555-123-4567">>)),
    ?assertEqual({ok, <<"+447700900123">>}, 
                connect_phone:format_e164(<<"+44 7700 900123">>)).

test_phone_info() ->
    % Test getting phone info for valid numbers
    case connect_phone:get_phone_info(<<"+15551234567">>) of
        #{valid := true, phone := <<"+15551234567">>} -> ok;
        Other1 -> ?assert(false, {unexpected_response, Other1})
    end,
    
    case connect_phone:get_phone_info(<<"+447700900123">>) of
        #{valid := true, phone := <<"+447700900123">>} -> ok;
        Other2 -> ?assert(false, {unexpected_response, Other2})
    end.

%%%===================================================================
%%% Utility Function Tests
%%%===================================================================

utility_test_() ->
    {setup, fun setup/0, fun cleanup/1, [
        {"Country info extraction", fun test_country_info/0},
        {"E164 format validation", fun test_e164_validation/0}
    ]}.

test_country_info() ->
    % Test extracting country information
    case connect_phone:extract_country_info(<<"+15551234567">>) of
        {ok, #{code := <<"1">>, id := <<"US">>, name := <<"United States">>}} -> ok;
        Other1 -> 
            io:format("Unexpected country info for +15551234567: ~p~n", [Other1]),
            ?assert(false)
    end,
    
    case connect_phone:extract_country_info(<<"+447700900123">>) of
        {ok, #{code := <<"44">>, id := <<"GB">>, name := <<"United Kingdom">>}} -> ok;
        Other2 -> 
            io:format("Unexpected country info for +447700900123: ~p~n", [Other2]),
            ?assert(false)
    end,
    
    % Invalid input
    ?assertMatch({error, _}, connect_phone:extract_country_info(<<"invalid">>)).

test_e164_validation() ->
    % Valid E164 formats
    ?assertEqual({ok, <<"+15551234567">>}, connect_phone:format_e164(<<"+15551234567">>)),
    ?assertEqual({ok, <<"+447700900123">>}, connect_phone:format_e164(<<"+447700900123">>)),
    
    % Invalid formats
    ?assertMatch({error, _}, connect_phone:format_e164(<<"invalid">>)),
    ?assertMatch({error, _}, connect_phone:format_e164(<<"123">>)).

%%%===================================================================
%%% Account ID Specific Tests
%%%===================================================================

account_id_scenarios_test_() ->
    {setup, fun setup/0, fun cleanup/1, [
        {"Login consistency", fun test_login_consistency/0},
        {"Registration validation", fun test_registration_validation/0},
        {"Cross-region consistency", fun test_cross_region_consistency/0}
    ]}.

test_login_consistency() ->
    % Same user trying to login with different formatting
    % Should all normalize to same account ID
    UserInputs = [
        <<"+1 555 123 4567">>,
        <<"+1-555-123-4567">>,
        <<"+1.555.123.4567">>,
        <<"+1(555)123-4567">>,
        <<"+15551234567">>
    ],
    
    Results = [connect_phone:normalize_account_id(Input) || Input <- UserInputs],
    
    % All should succeed
    [?assertMatch({ok, _}, Result) || Result <- Results],
    
    % All should produce the same account ID
    AccountIds = [AccountId || {ok, AccountId} <- Results],
    [?assertEqual(hd(AccountIds), AccountId) || AccountId <- AccountIds].

test_registration_validation() ->
    % Test registration scenarios
    
    % Valid registrations - require international format
    ?assertMatch({ok, _}, connect_phone:normalize_account_id(<<"+15551234567">>)),
    ?assertMatch({ok, _}, connect_phone:normalize_account_id(<<"+447700900123">>)),
    
    % Invalid registrations should be rejected
    ?assertMatch({error, _}, connect_phone:normalize_account_id(<<"123">>)),
    ?assertMatch({error, _}, connect_phone:normalize_account_id(<<"555-12">>)).

test_cross_region_consistency() ->
    % International numbers should work consistently
    InternationalNumber = <<"+447700900123">>,
    
    % Should normalize the same way
    {ok, AccountId1} = connect_phone:normalize_account_id(InternationalNumber),
    {ok, AccountId2} = connect_phone:normalize_account_id(<<"+44 7700 900123">>),  % With spaces
    {ok, AccountId3} = connect_phone:normalize_account_id(<<"+44-7700-900123">>), % With dashes
    
    ?assertEqual(AccountId1, AccountId2),
    ?assertEqual(AccountId2, AccountId3).

%%%===================================================================
%%% Error Handling Tests
%%%===================================================================

error_handling_test_() ->
    {setup, fun setup/0, fun cleanup/1, [
        {"Invalid input types", fun test_invalid_input_types/0},
        {"Malformed numbers", fun test_malformed_numbers/0},
        {"Empty inputs", fun test_empty_inputs/0}
    ]}.

test_invalid_input_types() ->
    % Non-binary phone numbers
    ?assertMatch({error, _}, connect_phone:normalize_account_id(123456789)),
    ?assertMatch({error, _}, connect_phone:normalize_account_id("5551234567")),
    
    % Other invalid types  
    ?assertMatch({error, _}, connect_phone:normalize_account_id(undefined)),
    ?assertMatch({error, _}, connect_phone:normalize_account_id(["+15551234567"])).

test_malformed_numbers() ->
    MalformedNumbers = [
        <<"++15551234567">>,  % Double plus
        <<"+-15551234567">>,  % Plus minus
        <<"+1555a1234567">>,   % Contains letters
        <<"+1555123456789012">>, % Way too long
        <<"+1555123">>         % Too short for US
    ],
    
    [?assertMatch({error, _}, connect_phone:normalize_account_id(Number)) 
     || Number <- MalformedNumbers].

test_empty_inputs() ->
    ?assertMatch({error, _}, connect_phone:normalize_account_id(<<>>)),
    ?assertMatch({error, _}, connect_phone:normalize_account_id(<<"   ">>)),
    ?assertMatch({error, _}, connect_phone:normalize_account_id(<<"+">>)).

%%%===================================================================
%%% Performance Tests (Basic)
%%%===================================================================

performance_test_() ->
    {setup, fun setup/0, fun cleanup/1, [
        {"Bulk normalization", {timeout, 10, fun test_bulk_normalization/0}}
    ]}.

test_bulk_normalization() ->
    % Test that we can handle multiple normalizations efficiently
    TestNumbers = [
        <<"+15551234567">>,
        <<"+447700900123">>,
        <<"+4915123456789">>,
        <<"+33123456789">>,
        <<"+31612345678">>
    ],
    
    Start = os:system_time(microsecond),
    
    Results = [connect_phone:normalize_account_id(Number) || Number <- TestNumbers],
    
    End = os:system_time(microsecond),
    Duration = End - Start,
    
    % Should complete within reasonable time
    ?assert(Duration < 1000000),  % Less than 1 second
    
    % Should have results for all test cases
    ?assertEqual(length(TestNumbers), length(Results)),
    
    % At least some should succeed (all valid numbers should work)
    SuccessCount = length([Result || {ok, _} = Result <- Results]),
    ?assert(SuccessCount >= 3).  % Most should succeed 