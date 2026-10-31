export ANSIBLE_COLLECTIONS_PATH := $(CURDIR)/.ansible/collections:$(HOME)/.ansible/collections:/usr/share/ansible/collections
PYTHON ?= python3
ANSIBLE_PLAYBOOK ?= ansible-playbook
ANSIBLE_ARGS ?=

.PHONY: storage-deps storage-check storage-k3s1 storage-arsene
storage-deps: .ansible/collections/ansible_collections/ansible/posix/MANIFEST.json

.ansible/collections/ansible_collections/ansible/posix/MANIFEST.json: ansible/collections/requirements.yml
	ansible-galaxy collection install --force -r $< -p .ansible/collections

storage-check: storage-deps
	$(ANSIBLE_PLAYBOOK) --syntax-check ansible/playbooks/database-storage-k3s1.yml
	$(ANSIBLE_PLAYBOOK) --syntax-check ansible/playbooks/database-storage-arsene.yml
	ansible-lint ansible/playbooks/database-storage-k3s1.yml ansible/playbooks/database-storage-arsene.yml

storage-k3s1: storage-deps
	$(ANSIBLE_PLAYBOOK) ansible/playbooks/database-storage-k3s1.yml $(ANSIBLE_ARGS)

storage-arsene: storage-deps
	$(ANSIBLE_PLAYBOOK) ansible/playbooks/database-storage-arsene.yml $(ANSIBLE_ARGS)

.PHONY: development-check
development-check:
	$(PYTHON) scripts/development/validate_templates.py .validation/development
	BROWNROOK_DEV_SECRETS_FILE="$(CURDIR)/.validation/development/synthetic-secrets.yml" $(ANSIBLE_PLAYBOOK) --syntax-check ansible/playbooks/development-backends.yml
	$(ANSIBLE_PLAYBOOK) --syntax-check ansible/playbooks/validate-development-backends.yml
	ansible-lint ansible/playbooks/development-backends.yml ansible/playbooks/validate-development-backends.yml

.PHONY: ha-check ha-preflight
ha-check:
	@for script in scripts/kan-132/*.sh; do bash -n "$$script" || exit; done
	$(PYTHON) -m pytest -q tests/kan132

ha-preflight:
	bash scripts/kan-132/preflight.sh
