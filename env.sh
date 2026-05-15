#!/bin/bash

ROOT="/home/dane/workspace/freedom-formation"

nvm use v25.6.1
alias web='cd $ROOT/playground && pnpm web'
alias mobile='cd $ROOT/playground/packages/mobile && npx expo start'
