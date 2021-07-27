#!/bin/bash

set -euf -o pipefail

# Change working directory
cd /ms-playwright

# Generate the tests
node ./generate.js

# Wait for Retool to start
wait-for-it api:3000 -t 120

# Run the tests
npx playwright test
