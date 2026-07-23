#!/bin/bash

# to deploy hermes container with persona-db skills (from hermesa3-clone-v1-sanitized.tar.gz) 
ansible-playbook -i localhost, -c local ./03-deploy-hermes-container.yml

# to deploy persona-db-api container,(/w persona-db-rel-1.0.tar.gz persona-db repo)
bash ./deploy-persona-db-api.sh
