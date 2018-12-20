#!/bin/bash

set -e
set -x

MIN_PCT=1
MAX_PCT=99

PLATFORM=mac TEST_NAME=rails_10k erb single_csv_set.html.erb > output/mac_rails_10k.html
PLATFORM=mac TEST_NAME=rack_10k erb single_csv_set.html.erb > output/mac_rack_10k.html

PLATFORM=ubuntu TEST_NAME=rails_10k erb single_csv_set.html.erb > output/ubuntu_rails_10k.html
PLATFORM=ubuntu TEST_NAME=rails_1mil erb single_csv_set.html.erb > output/ubuntu_rails_1mil.html
