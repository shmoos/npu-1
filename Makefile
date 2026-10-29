PYTHON ?= .venv/bin/python

.PHONY: help smoke lint test-pe test-array test-model regression
help:
	@printf '%s\n' 'smoke       Validate local simulator and failure detection' 'lint        Lint all RTL with warnings treated as errors' 'test-pe     Exhaustive, directed, random and protocol PE tests' 'test-array  Systolic tile, cycle, pause and operand-tag checks' 'test-model  Check the independent Python references' 'regression  Run all implemented local checks'
smoke:
	"$(PYTHON)" scripts/run_verification.py --suite smoke
lint:
	"$(PYTHON)" scripts/run_verification.py --suite lint
test-pe:
	"$(PYTHON)" scripts/run_verification.py --suite pe
test-array:
	"$(PYTHON)" scripts/run_verification.py --suite array
test-model:
	PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 "$(PYTHON)" -m pytest -q tests
regression:
	"$(PYTHON)" scripts/run_verification.py --suite all
