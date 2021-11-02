# Screwdriver AWS Integration Producer Scripts
Infrastructure-as-code script for creating a Managed Kafka Service and VPC for Screwdriver AWS Integration

## Introduction

This repository is meant to serve as an install/uninstall/update script to provision necessary cloud infrastructure resources required for Screwdriver AWS Integration. The following are the resources created by the installation script by default:
- 1 AWS Managed Kafka Cluster
- 3 AWS VPC Endpoint Service  (1 for each availability zone of MSK broker endpoint)
- 3 Network Load Balancers (1 for each endpoint service)
- 3 Target Groups (1 for each load balancer)
- 1 Security Group For AWS MSK
- 1 Customer managed KMS Key for the MSK cluster
The following resources will be crated with new creation:
- 1 VPC based on the provided cidr block
- Private subnets
- Public subnets
- NAT Gateway
- Internet Gateway
- Route Table

If you opt for installation with an existing vpc, it will skip the vpc infrastructure creation

This script uses open source tool [terraform](https://www.terraform.io/) to provision all the resources

### Dependencies

The followings are the external dependencies required to run this onboarding script:

- [terraform](https://github.com/hashicorp/terraform/releases/latest)
- [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)

All of these tools can be installed via Homebrew on Mac OS X.

## Prerequisite
Screwdriver API's must be deployed in the same AWS account and region which will connect to the producer service and queue.
Also a Amazon Secret Manager secret needs to be created manually (for now) with secret values that will be used in the consumer service. 

## Instructions

To get started, update the var file with the required details. Please refer to [`env.tfvars`](./env.tfvars) for the variables list.
Example var file for prod is at [`example-prod`](./example-prod.tfvars).

Second, configure the AWS CLI by running `aws configure` with your AWS credentials and select profile for the desired account.
```
export AWS_PROFILE=<profile_name>
export AWS_REGION=<region_name>
```

Next, to begin the infrastructure provisioning process:

### install
```sh
# by default, setup.sh will try to find "env.tfvars"
./setup.sh 
```

`./setup.sh` will first validate env.tfvars for all variables and use default for the ones not found, it will then run terraform init, followed by plan and apply to provision infrastructure.

For step by step installation, you can use the following options
```sh
# -i flag will run terraform init and verify backend infrastructure
./setup.sh -i
# -p flag will run terraform plan and create a tf plan
./setup.sh -p
# -a flag will run terraform apply and create the resources
./setup.sh -a
```

You can also run validation to check for errors before running plan and after running apply by using
the -v flag
```sh
./setup.sh -v
```

Alternatively, to uninstall all infrastructure

```sh
./setup.sh -d
```
### Considerations for VPC setup

The the number of resources in the infrastructure will be created based on the VPC configuration. There are 2 scenarios

- [Consumer Resources with Existing VPC](#consumer-svc-with-existing-vpc)
- [Consumer Resources with New VPC](#consumer-svc-with-new-vpc)

#### Consumer Resources with Existing VPC

For existing VPC and subnets, all we need are the resource ID of the VPC and the cidr's of the private subnets. If using existing VPC it needs to have both private and public subnets as the resources will be created in private subnets. Also the private subnets should have outbound access to the internet. Therefore, we highly recommend reviewing your existing VPC to see if it fits or a new one should be created instead. Additionally, you can update the other variables like vpc name and consumer function name.

Example configuration for exiting vpc:
```yaml
aws_region="us-west-2"
tf_backend_bucket="sd-aws-consumer-tf-backend-11111111"
private_subnets   = ["10.10.104.0/25", "10.10.104.128/25", "10.10.105.0/25", "10.10.105.128/25"]
vpc_id            ="vpc-1234"
msk_cluster_name  = "beta-sd-msk"
msk_ebs_vol       = 100
msk_instance_type = "kafka.t3.small"
msk_nodes_count   = 3
msk_secret_arn    = "arn:someExampleSecret"
msk_secret_name   = "AmazonMSK_BETA_SD_SECRET"
tags              = {PRODUCT:"SCREWDRIVER",ENVIRONMENT:"beta",SERVICE:"sd/producer"}
deploy_env        = "beta"
```
#### Consumer Resources with New VPC

In this case a VPC will be created and consumer svc will be provisioned in the new vpc. The required configuration needed for a new VPC setup are the VPC CIDR, the list of private and public subnet cidrs and the availability zones. The VPC CIDR prefix must be between `/16` and `/24`. Additionally, you can update the other variables like vpc name and consumer function name.

Example configuration is new vpc:
```yaml
aws_region="us-west-2"
tf_backend_bucket="sd-aws-consumer-tf-backend-11111111"
cidr_block        = "10.10.104.0/22"
private_subnets   = ["10.10.104.0/25", "10.10.104.128/25", "10.10.105.0/25", "10.10.105.128/25"]
public_subnets    = ["10.10.106.0/25", "10.10.106.128/25", "10.10.107.0/25", "10.10.107.128/25"]
azs               = ["us-west-2a", "us-west-2b", "us-west-2c", "us-west-2d"]
vpc_name          ="sd-producer"
msk_cluster_name  = "beta-sd-msk"
msk_ebs_vol       = 100
msk_instance_type = "kafka.t3.small"
msk_nodes_count   = 3
msk_secret_arn    = "arn:someExampleSecret"
msk_secret_name   = "AmazonMSK_BETA_SD_SECRET"
tags              = {PRODUCT:"SCREWDRIVER",ENVIRONMENT:"beta",SERVICE:"sd/producer"}
deploy_env        = "beta"
```
## Configurations

The config variables are all part of .tfvars file. These variables will be used in creating the resources.
### Config Definitions

The following table describes all the configurable variables defined in `setup.tfvars`

| Name | Type | Description |
| - | - | - |
| aws_region <sup>*</sup> | String | AWS Region where resources will be provisioned |
| tf_backend_bucket <sup>*</sup> | String | Terraform backend S3 bucket for storing tf state |
| msk_cluster_name <sup>*</sup> | String | Screwdriver MSK cluster name |
| msk_ebs_vol <sup>*</sup> | Integer | EBS volume size for MSK cluster |
| msk_instance_type <sup>*</sup> | String | Type of ec2 instance for kafka cluster  |
| msk_nodes_count <sup>*</sup> | Integer | Number of nodes for Kafka Cluster |
| msk_secret_arn <sup>*</sup> | String | AWS Arn of the MSK secret for authentication |
| msk_secret_name <sup>*</sup> | String | Name of the MSK secret for authentication |
| vpc_id <sup>*</sup> | String | User VPC Id  |
| private_subnets <sup>*</sup> | List | List of private subnets |
| public_subnets <sup>#</sup> | List | List of public subnets |
| cidr_block <sup>#</sup> | String | CIDR block for the user vpc |
| vpc_name <sup>#</sup> | String | Name of the user vpc |
| azs <sup>#</sup> | List | List of availability zones |
| tags <sup>*</sup> | Map | Map of tags to be used for resource creation |
| deploy_env <sup>*</sup> | String | The environment prefix where resources will be deployed |

<i><sup>*</sup> required config</i>

<i><sup>#</sup> required config when creating new vpc</i>

### Provider config vars
```aws_region="us-west-2"
tf_backend_bucket="sd-aws-producer-tf-backend-<accountId>" #replace accountId
```
### Msk cluster config vars
```msk_cluster_name="example-sd-msk"
msk_ebs_vol=100
msk_instance_type=""kafka.t3.small""
msk_nodes_count=3
msk_secret_arn=""
msk_secret_name="AmazonMSK_EXAMPLE_SD_SECRET"
```
### Config for VPC (existing or new)
```
vpc_id=null
private_subnets=["10.10.106.0/25", "10.10.106.128/25", "10.10.107.0/25", "10.10.107.128/25"]
cidr_block="10.10.104.0/22"
public_subnets=["10.10.104.0/25", "10.10.104.128/25", "10.10.105.0/25", "10.10.105.128/25"]
azs=["us-west-2a", "us-west-2b", "us-west-2c", "us-west-2d"]
vpc_name="screwdriver-producer"
```
