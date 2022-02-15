#!/bin/bash
set -eo pipefail
programname=$0

CWD=$(dirname ${BASH_SOURCE})
declare TF_CMD
declare TF_VAR_FILE_NAME="./env.tfvars.json"

function usage {
    echo "usage: $programname [-ipavro]"
    echo "  -i|--init     runs the init script"
    echo "  -p|--plan     runs the infra plan and produces an output file producer_infra.tfplan"
    echo "  -a|--apply    runs the apply script with the plan producer_infra.tfplan"
    echo "  -v|--validate runs the validate script"
    echo "  -r|--refresh  runs the refresh script"
    echo "  -o|--output   returns the output"
    echo "  -all|         runs all commands in sequence|for advanced usage"
    exit 1
}

check_dependencies() {
    declare -r deps=(terraform aws)
    declare -r install_docs=(
        'https://github.com/hashicorp/terraform/releases/latest'
        'https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html'
    )

    for ((i = 0, f = 0; i < ${#deps[@]}; i++)); do
        if ! command -v ${deps[$i]} &>/dev/null; then
            ((++f)) && echo "'${deps[$i]}' command is not found. Please refer to ${install_docs[$i]} for proper installation."
        fi
    done

    if [[ $f -ne 0 ]]; then
        exit 127
    fi
}

read_var_file() {
    data=`echo $1 | \
        jq '. | to_entries[]| select(.value | . == null or . == "") 
        | if .value == "" then .value |= "\\"\\(.)\\"" else . end | "\\(.key): \\(.value)"'`
    local dirtyfile=0
    if [ ! -z "$data" ];then
        echo "Fix keys: $data"
        dirtyfile=0
    fi
    return $dirtyfile
}

check_svc_vars() {
    if  [ -e $TF_VAR_FILE_NAME ]; then 
        tfvarfile=$(cat $TF_VAR_FILE_NAME)
        read_var_file "$tfvarfile"
        dirtyfile=$0
        if [ "$dirtyfile" = true ];then
            echo "Please fix env.tfvars.json to proceed!!" 
            exit 1
        fi
        printf "===env varfile===\n"
        echo "${tfvarfile}"
        printf "===end varfile===\n"
    else
        echo "Please add file env.tfvars.json"
        exit 1
    fi
}

read_input() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -i|--init) 
                TF_CMD="init"
                shift 1
                ;;
            -d|--destroy)
                TF_CMD="destroy"
                shift 1
                ;;
            -p|--plan) 
                TF_CMD="plan" 
                shift 1
                ;;
            -a|--apply) 
                TF_CMD="apply" 
                shift 1
                ;;
            -r|--refresh) 
                TF_CMD="refresh" 
                shift 1
                ;;
            -v|--validate)
                TF_CMD="validate"
                shift 1 
                ;;
            -all)
                TF_CMD="all"
                shift 1 
                ;;
            -o|--output)
                TF_CMD="output"
                shift 1 
                ;;
            [?])
                usage
                exit 1
        esac
    done
}

run_tf_cmd() {
    tfvarfile=$1
    tfplanoutputfile=$2
    targetname=$3
    echo "===Runnning terraform $TF_CMD script==="
    case "$TF_CMD" in
        "destroy") terraform destroy  -auto-approve $tfplanoutputfile ;;
        "validate") terraform validate ;;
        "init") terraform init -var-file=$tfvarfile ;;
        "plan") terraform plan -var-file=$tfvarfile -out $tfplanoutputfile ;;
        "refresh") terraform refresh -var-file=$tfvarfile ;;
        "apply") terraform apply -auto-approve $tfplanoutputfile ;;
        "output") get_tf_output ;;
        *)
            terraform init
            terraform plan -var-file=$tfvarfile -out $tfplanoutputfile
            terraform apply -auto-approve $tfplanoutputfile
        ;;
    esac
}

get_tf_output() {
    output_var=$1
    terraform output $output_var
}

main() {
    check_dependencies
    
    read_input "$@"
    
    check_svc_vars

    run_tf_cmd "$TF_VAR_FILE_NAME" "producer_infra.tfplan"
    
    msk_cluster=`terraform state list 2>&1`

    get_tf_output
}

main "$@" 