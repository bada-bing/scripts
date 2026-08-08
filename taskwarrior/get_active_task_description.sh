#!/bin/bash

task +ACTIVE export 2>/dev/null | jq -r 'sort_by(.id) | last | .description // empty'
