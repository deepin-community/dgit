# usage: tests/using-intree make -f tests/Makefile
# optionally setting
#   TESTSCRIPTS='tests/tests/foo tests/tests/bar')
#   DGIT_TEST_RETRY_COUNT=<a smallish integer>

TESTSCRIPTS ?= $(shell tests/enumerate-tests)
TESTNAMES := $(notdir $(TESTSCRIPTS))

all: $(foreach t,$(TESTNAMES),tests/tmp/$t.ok)
	@echo "ALL PASSED$${DGIT_TESTS_PROGRESSIVE+ AT SOME POINT}"

tests/tmp/%.ok: tests/tests/%
ifeq ($(DGIT_TEST_RETRY_COUNT),)
	$(DGIT_TEST_RUN_PFX) tests/tests/$* >tests/tmp/$*.log 2>&1
else
	@for retry in $$( seq 1 $(DGIT_TEST_RETRY_COUNT) ); do		\
		echo "[$$retry] $*";					\
	$(DGIT_TEST_RUN_PFX) tests/tests/$* >tests/tmp/$*.$$retry.log 2>&1; \
		rc=$$?;							\
		if [ $$rc = 0 ]; then exit 0; fi;			\
		echo >&2 "[$$retry] $* TEST FAILED $$rc";		\
	done; exit $$rc
endif
	@touch $@
