#!/bin/bash

# TODO use task +ACTIVE export and jq to simplify the command
task _get $(task +ACTIVE ls | tail -n +2 | sed -e '$d' -e '$d' | sort -k 1 -n | tail -n 1 | awk '{print $1}').description
