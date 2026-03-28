#!/bin/bash

# sccache credentials for Backblaze B2
# used by shared.sh to enable distributed compilation caching

export SCCACHE_BUCKET="chromium-sccache"
export SCCACHE_REGION="us-east-005"
export SCCACHE_ENDPOINT="https://s3.us-east-005.backblazeb2.com"
export AWS_ACCESS_KEY_ID="005c79d6a06428d0000000002"
export AWS_SECRET_ACCESS_KEY="K005D9BiaivjQO6BjvI3VqorMcbo0SI"
export SCCACHE_S3_USE_SSL="true"
