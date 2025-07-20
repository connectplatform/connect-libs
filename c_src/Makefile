
PROJECT_NIF_NAME=phonenumber_util_nif

include nif.mk

ifeq ($(UNAME_SYS), darwin)
	ICU_PATH := /usr/local/Cellar/icu4c
	ICU_VERSION_CMD := $(shell ls $(ICU_PATH))
	ICU_VERSION := $(shell echo $(ICU_VERSION_CMD) | awk '{print $0}')

	PROTO_PATH := /usr/local/Cellar/protobuf
	PROTO_VERSION_CMD := $(shell ls $(PROTO_PATH))
	PROTO_VERSION := $(shell echo $(PROTO_VERSION_CMD) | awk '{print $0}')

	CXXFLAGS += -I $(PROTO_PATH)/$(PROTO_VERSION)/include

	LDFLAGS +=  -L/usr/local/lib/ \
				-L$(ICU_PATH)/$(ICU_VERSION)/lib \
			    -lphonenumber \
				-lboost_thread-mt \
				-lstdc++ \
			    -Wl,-U,_enif_make_new_binary \
				-Wl,-U,_enif_make_tuple \
				-Wl,-U,_enif_make_ulong \
				-Wl,-U,_enif_make_list_from_array \
				-Wl,-U,_enif_make_int \
				-Wl,-U,_enif_make_existing_atom \
				-Wl,-U,_enif_make_badarg \
				-Wl,-U,_enif_make_atom \
				-Wl,-U,_enif_is_identical \
				-Wl,-U,_enif_inspect_iolist_as_binary \
				-Wl,-U,_enif_get_ulong \
				-Wl,-U,_enif_get_tuple \
				-Wl,-U,_enif_get_int
else
	LDFLAGS +=  -l:libphonenumber.a \
				-lboost_thread
endif

CXXFLAGS +=  -fPIC -g -Wextra -Werror -std=c++11 -fno-exceptions -Wno-missing-field-initializers -Wno-unused-parameter -Wno-deprecated-declarations -Wno-switch \
 		     -I $(BASEDIR)/_build/deps/libphonenumber/cpp/build/install/include  \
 		     -DI18N_PHONENUMBERS_NO_THREAD_SAFETY

LDFLAGS +=  -L$(BASEDIR)/_build/deps/libphonenumber/cpp/build \
			-lboost_system \
			-lboost_date_time \
			-licui18n \
			-licuuc \
			-lprotobuf


