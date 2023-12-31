# Adds .env variables to the environment, used for secrets
include .env
export

# Deployment variables
export ROOT_DIR ?= $(shell pwd)
export APP_DIR ?= ${ROOT_DIR}/app
export ORGANIZATION ?= $(shell jq -r '.tags.org' ${APP_DIR}/config.json)
export APP_NAME ?= $(shell jq -r '.tags.app' ${APP_DIR}/config.json)

target:
	$(info ${HELP_MESSAGE})
	@exit 0

check-env:
ifndef CDK_DEFAULT_ACCOUNT
$(error CDK_DEFAULT_ACCOUNT is not set. Please select an AWS profile to use.)
endif
ifndef CDK_DEFAULT_REGION
$(error CDK_DEFAULT_REGION is not set. Please select an AWS profile to use.)
endif
	@echo "Found environment variables"

 # Deploy services
deploy: check-env
	$(info [*] Deploying ${APP_NAME} to ${CDK_DEFAULT_ACCOUNT})
	@echo "Creating EC2 key pair..."
	$(MAKE) key-pair.create
	@echo "Deploying CDK stack..."
	@cd ${APP_DIR} && cdk deploy --require-approval never
	# $(MAKE) opensearch.wait
	# @echo "Creating OpenSearch schema..."
	# $(MAKE) opensearch.schema.create

destroy:
	$(info [*] Destroying ${APP_NAME} in ${CDK_DEFAULT_ACCOUNT})
	@cd ${APP_DIR} && cdk destroy
	$(MAKE) key-pair.delete

key-pair.create: ##=> Checks if the key pair already exists and creates it if it does not
	@echo "$$(date -u +'%Y-%m-%d %H:%M:%S.%3N') - Checking for key pair $$EC2_KEY_PAIR_NAME" 2>&1 | tee -a $$CFN_LOG_PATH
	@EC2_KEY_PAIR_NAME="$$(jq -r '.services.opensearch.env.ssh_key_name' ${APP_DIR}/config.json)" && \
	key_pair="$$(aws ec2 describe-key-pairs --key-name $$EC2_KEY_PAIR_NAME | jq -r --arg KEY_PAIR "$$EC2_KEY_PAIR_NAME" '.KeyPairs[] | select(.KeyName == $$KEY_PAIR).KeyName')" && \
	[ "$$key_pair" ] && echo "Key pair found: $$key_pair" && exit 0 || echo "No key pair found..." && \
	echo "Creating EC2 key pair \"$$EC2_KEY_PAIR_NAME\"" && \
	aws ec2 create-key-pair --key-name $$EC2_KEY_PAIR_NAME | jq -r '.KeyMaterial' > ${ROOT_DIR}/$$EC2_KEY_PAIR_NAME.pem

key-pair.delete:
	@EC2_KEY_PAIR_NAME="$$(jq -r '.services.opensearch.env.ssh_key_name' ${APP_DIR}/config.json)" && \
	aws ec2 delete-key-pair --key-name "$$EC2_KEY_PAIR_NAME" && \
	mv ${ROOT_DIR}/$$EC2_KEY_PAIR_NAME.pem ${ROOT_DIR}/deprecated-key-$$(date -u +'%Y-%m-%d-%H-%M').pem

opensearch.status:
	@instance_id=$$(aws ssm get-parameters --names "/${ORGANIZATION}/${APP_NAME}/InstanceId" | jq -r '.Parameters[0].Value') && \
	aws ec2 describe-instances | \
		jq --arg iid "$$instance_id" '.Reservations[].Instances[] | select(.InstanceId == $$iid) | {InstanceId, InstanceType, "Status": .State.Name, StateTransitionReason, ImageId}'

opensearch.start:
	@echo "Starting $${APP_NAME} server..."
	@instance_id=$$(aws ssm get-parameters --names "/${ORGANIZATION}/${APP_NAME}/InstanceId" | jq -r '.Parameters[0].Value') && \
	response=$$(aws ec2 start-instances --instance-ids $$instance_id) && \
	echo $$response | jq -r
	$(MAKE) opensearch.wait

opensearch.stop:
	@echo "Stopping $${APP_NAME} server..."
	@instance_id=$$(aws ssm get-parameters --names "/${ORGANIZATION}/${APP_NAME}/InstanceId" | jq -r '.Parameters[0].Value') && \
	response=$$(aws ec2 stop-instances --instance-ids $$instance_id) && \
	echo $$response | jq -r

opensearch.reboot:
	@echo "Rebooting $${APP_NAME} server..."
	@instance_id=$$(aws ssm get-parameters --names "/${ORGANIZATION}/${APP_NAME}/InstanceId" | jq -r '.Parameters[0].Value') && \
	response=$$(aws ec2 reboot-instances --instance-ids $$instance_id) && echo "$$response"
	$(MAKE) opensearch.wait

opensearch.wait:
	@endpoint=$$(aws ssm get-parameters \
		--names "/${ORGANIZATION}/${APP_NAME}/Ec2OpenSearchEndpoint" | jq -r '.Parameters[0].Value') && \
	timeout=360 && \
	counter=0 && \
	echo "Waiting for response from OpenSearch at $$endpoint..." && \
	until [ $$(curl -s -o /dev/null -w "%{http_code}" $$endpoint/v1) -eq 200 ] ; do \
		printf '.' ; \
		sleep 1 ; \
		counter=$$((counter + 1)) ; \
		[ $$counter -eq $$timeout ] && break || true ; \
	done && \
	[ $$counter -eq $$timeout ] && $$(echo "Operation timed out!" && exit 1) || echo "Ready"

opensearch.get.endpoint:
	@endpoint=$$(aws ssm get-parameters --names "/${ORGANIZATION}/${APP_NAME}/Ec2OpenSearchEndpoint" | jq -r '.Parameters[0].Value') && \
	echo "$$endpoint"

opensearch.schema.create:
	@bash scripts/create_schema.sh

opensearch.schema.delete:
	@printf "Deleting the schema will remove all data. Do you wish to continue? [y/N] " && \
	read ans && [ $${ans:-N} = y ] && \
	bash scripts/delete_schema.sh

define HELP_MESSAGE

	Environment variables:

	CDK_DEFAULT_ACCOUNT: "${CDK_DEFAULT_ACCOUNT}":
		Description: AWS account ID for deployment

	CDK_DEFAULT_REGION: "${CDK_DEFAULT_REGION}":
		Description: AWS region for deployment

	ROOT_DIR: "${ROOT_DIR}":
		Description: Project directory root

	APP_DIR: "${APP_DIR}":
		Description: Application directory containing the full source code

	ORGANIZATION: "${ORGANIZATION}":
		Description: Organization name, declared in `config.json`

	APP_NAME: "${APP_NAME}":
		Description: Application name, declared in `config.json`
		
	Common usage:

	...::: Deploy all CloudFormation based services :::...
	$ make deploy

	...::: Delete all CloudFormation based services and data :::...
	$ make delete

endef
