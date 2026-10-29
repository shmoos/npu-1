PYTHON ?= python3
.PHONY: regression lint test-model test-pe test-array test-core test-axil demo host help
help:
	@echo 'make regression | demo | lint | test-model | test-pe | test-array | test-core | test-axil | host'
regression:
	$(PYTHON) scripts/verify.py
lint test-pe test-array test-core test-axil demo:
	$(PYTHON) scripts/verify.py --only $@
test-model:
	$(PYTHON) -m pytest -q tests
host:
	$(MAKE) -C host
