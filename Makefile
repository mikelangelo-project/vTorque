#
# Copyright 2016 HLRS, University of Stuttgart
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#


#
# prints out available targets
#
info:
	echo -e "Choose from:\n  install\n  permissions\n  permissions-dev\n  permissions-git-commit\n setup-nodes\n  revert-nodes\n"; \


#
# Installs vTorque
#
install:
	echo "TODO" \


#
# set permissions for production
#
permissions:
	chown -R root:root ./; \
	chown -R root:mikedev ./module_file; \
	chmod 555 ./module_file; \
	chmod 444 ./module_file/*; \
	chmod 555 ./src/scripts; \
	chmod 500 ./src/scripts/*; \
	chmod 555 ./src/templates; \
	chmod 444 ./src/templates/*; \
	chmod 555 ./src/common; \
	chmod 444 ./src/common/*; \
	chmod 555 ./src/qsub; \
	chmod -R 555 ./test; \
	chmod 444 ./contrib/*; \
	chmod -R 555 ./components/*; \
	echo "Done"; \


#
# sets permissions for development
#
permissions-dev:
	chown -R root:mikedev ./; \
	chmod 775 ./module_file; \
	chmod 664 ./module_file/*; \
	chmod 555 ./src/scripts; \
	chmod 500 ./src/scripts/*; \
	chmod 775 ./src/templates; \
	chmod 664 ./src/templates/*; \
	chmod 775 ./src/common; \
	chmod 664 ./src/common/*; \
	chmod 775 ./src/qsub; \
	chmod -R 775 ./test/*; \
	chmod 664 ./contrib/*; \
	chmod -R 775 ./components/*; \
	echo "Done"; \


#
# set permissions for git commits
#
permissions-git-commit:
	chown -R $(USER):$(USER) ./ \
	chmod 775 -R ./ \

#
# rename current/orig scripts in place
#
setup-nodes:
	pdsh -a "sudo rename -v 's/(.*)\$$$\/\$$$\1.orig.norun/' /var/spool/torque/mom_priv/{pro,epi}logue{.user,}{.parallel,.precancel,} 2>/dev/null;" | sort; \
	pdsh -a "sudo ln -sf $(CURDIR)/src/scripts/{prologue{,.parallel},epilogue{,.parallel,.precancel}} /var/spool/torque/mom_priv/; sudo ls -al /var/spool/torque/mom_priv/ | grep logue;" | sort; \
	echo "Done"; \

#
# put original scripts back in place
#
revert-nodes:
	pdsh -a "sudo rm -f /var/spool/torque/mom_priv/{pro,epi}logue{.user,}{.parallel,.precancel,} 2> /dev/null;" | sort; \
	pdsh -a "sudo rename 's/\.orig\$$$\//' /var/spool/torque/mom_priv/{pro,epi}logue{.user,}{.parallel,.precancel,}.orig ;" | sort; \
	echo "Done"; \


