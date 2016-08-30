#!/bin/bash
#
# Copyright 2014 Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License").
# You may not use this file except in compliance with the License.
# A copy of the License is located at
#
#  http://aws.amazon.com/apache2.0
#
# or in the "license" file accompanying this file. This file is distributed
# on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either
# express or implied. See the License for the specific language governing
# permissions and limitations under the License.

. $(dirname $0)/common_functions.sh

if [ "$#" -ne 1 ]; then
  error_exit "no instance ip provided for de-registering"
fi

ip=$1
INSTANCE_ID=$(get_instance_id_from_ip $ip)
if [ $? != 0 -o -z "$INSTANCE_ID" ]; then
    error_exit "Unable to get this instance's ID; cannot continue."
fi

# Get current time
msg "Started $(basename $0) at $(/bin/date "+%F %T")"
start_sec=$(/bin/date +%s.%N)

set_flag "dereg" "true"

if [ -z "$ELB_LIST" ]; then
    error_exit "ELB_LIST is empty. Must have at least one load balancer to deregister from, or \"_all_\", \"_any_\" values."
elif [ "${ELB_LIST}" = "_all_" ]; then
    msg "Automatically finding all the ELBs that this instance is registered to..."
    get_elb_list $INSTANCE_ID
    if [ $? != 0 ]; then
        error_exit "Couldn't find any. Must have at least one load balancer to deregister from."
    fi
    set_flag "ELBs" "$ELB_LIST"
elif [ "${ELB_LIST}" = "_any_" ]; then
    msg "Automatically finding all the ELBs that this instance is registered to..."
    get_elb_list $INSTANCE_ID
    if [ $? != 0 ]; then
        msg "Couldn't find any, but ELB_LIST=any so finishing successfully without deregistering."
        set_flag "ELBs" ""
        finish_msg
        exit 0
    fi
    set_flag "ELBs" "$ELB_LIST"
fi

# Loop through all LBs the user set, and attempt to deregister this instance from them.
for elb in $ELB_LIST; do
    msg "Checking validity of load balancer named '$elb'"
    validate_elb $INSTANCE_ID $elb
    if [ $? != 0 ]; then
        msg "Error validating $elb; cannot continue with this LB"
        continue
    fi

    msg "Deregistering $INSTANCE_ID from $elb"
    deregister_instance $INSTANCE_ID $elb

    if [ $? != 0 ]; then
        error_exit "Failed to deregister instance $INSTANCE_ID from ELB $elb"
    fi
done

# Wait for all deregistrations to finish
msg "Waiting for instance to de-register from its load balancers"
for elb in $ELB_LIST; do
    wait_for_state $INSTANCE_ID "OutOfService" $elb
    if [ $? != 0 ]; then
        error_exit "Failed waiting for $INSTANCE_ID to leave $elb"
    fi
done

finish_msg
