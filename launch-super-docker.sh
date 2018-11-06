#!/bin/bash
#
# Script to help spin up A-Number Issuance Docker Containers
#

set -x

# Get IP address of local computer, needed to setup connection to Kafka
export host_ip=`ifconfig en0 | grep 'inet ' | cut -d' ' -f2`

# Clear out old containers. Not necessary every time but can help with build issues.
# NOTE this will destroy your existing Kafka topics/data!
# docker rm -f $(docker ps -aq)

################ Function to parse yaml files ################
# credit to https://github.com/jasperes/bash-yaml
function parse_yaml() {
    local yaml_file=$1
    local prefix=$2
    local s
    local w
    local fs

    s='[[:space:]]*'
    w='[a-zA-Z0-9_.-]*'
    fs="$(echo @|tr @ '\034')"

    sed -e "/- [^\"][^\'].*:/s|\([ ]*\)- \($s\)|\1-\n  \1\2|g" "$yaml_file" |

    sed -ne '/^--/s|--||g; s|\"|\\\"|g; s/\s*$//g;' \
        -e "/#.*[\"\']/!s| #.*||g; /^#/s|#.*||g;" \
        -e "s|^\($s\)\($w\)$s:$s\"\(.*\)\"$s\$|\1$fs\2$fs\3|p" \
        -e "s|^\($s\)\($w\)$s[:-]$s\(.*\)$s\$|\1$fs\2$fs\3|p" |

    awk -F"$fs" '{
        indent = length($1)/2;
        if (length($2) == 0) { conj[indent]="+";} else {conj[indent]="";}
        vname[indent] = $2;
        for (i in vname) {if (i > indent) {delete vname[i]}}
            if (length($3) > 0) {
                vn=""; for (i=0; i<indent; i++) {vn=(vn)(vname[i])("_")}
                printf("%s%s%s%s=(\"%s\")\n", "'"$prefix"'",vn, $2, conj[indent-1],$3);
            }
        }' |

    sed -e 's/_=/+=/g' |

    awk 'BEGIN {
             FS="=";
             OFS="="
         }
         /(-|\.).*=/ {
             gsub("-|\\.", "_", $1)
         }
         { print }'
}

function isNotEmpty() {
  [ ! -z $1 ]
}

function isEmpty() {
  [ -z $1 ]
}

function containsElement () {
  local e match="$1"
  shift
  for e; do [[ "$e" == "$match" ]] && return 0; done
  return 1
}

# Set yaml properties as bash variables
eval $(parse_yaml docker-config.yml)

# set project and service arrays as env variables
inputProjects=${projects[@]}
inputServices=${services[@]}

# if particular docker files are selected
# then use the particular ones
# else default to docker-compose.yml
if isEmpty ${dockerfiles[@]}; then
  dockerfiles+=( "docker-compose.yml" )
fi

# arguments are converted to an array
argArray=( "$@" )

# checks to see for the attached option
detach="-d"
if containsElement "-a" ${argArray[@]} ||  containsElement "--attach" ${argArray[@]}; then
  detach=
fi

# checks to see for the build option
if containsElement "-b" ${argArray[@]} || containsElement "--build" ${argArray[@]}; then
  build=1
fi

################ Function to start docker containers ################
function start() {
  if isNotEmpty $inputProjects; then
  # Projects list take priority when set
    echo "Starting services from defined project(s): $inputProjects"
    for project in $inputProjects; do
      # sets all the services under define section
      # based on the project name
      definedInputServiceTmp=define_$project[@]
      definedInputService=${!definedInputServiceTmp}

      # loops through each dockerfile provided
      for dockerfile in ${dockerfiles[@]}; do
        servicesToSpinUp=()
        # gets all the services in the dockerfile
        allServices=$( docker-compose -f $dockerfile config --services )
        for service in $allServices; do
          # if listed service is included in this docker-compose file
          # add to array
          if containsElement $service $definedInputService; then
            servicesToSpinUp+=( $service )
          fi
        done

        # rebuild the image to clear cached containers before running containers
        if [[ $build = "1"  ]]; then
          docker-compose -f $dockerfile build ${servicesToSpinUp[@]}
          docker-compose -f $dockerfile stop ${servicesToSpinUp[@]}
          docker-compose -f $dockerfile rm -f ${servicesToSpinUp[@]}
        fi
        # run dockercompose for selected dockerfile with services chosen and related to
        # docker file
        docker-compose -f $dockerfile up $detach --force-recreate ${servicesToSpinUp[@]}
      done
    done

  elif isNotEmpty $inputServices; then
  # If no projects are set then use defined services
    echo "Starting services from defined services"

    # loops through each dockerfile provided
    for dockerfile in ${dockerfiles[@]}; do
      servicesToSpinUp=()
      # gets all the services in the dockerfile
      allServices=$( docker-compose -f $dockerfile config --services )
      for service in $allServices; do
        # if listed service is included in this docker-compose file
        # add to array
        if containsElement $service $inputServices; then
          servicesToSpinUp+=( $service )
        fi
      done

      # rebuild the image to clear cached containers before running containers
      if [[ $build = "1"  ]]; then
        docker-compose -f $dockerfile build ${servicesToSpinUp[@]}
        docker-compose -f $dockerfile stop ${servicesToSpinUp[@]}
        docker-compose -f $dockerfile rm -f ${servicesToSpinUp[@]}
      fi

      # run dockercompose for selected dockerfile with services chosen and related to
      # docker file
      docker-compose -f $dockerfile up $detach --force-recreate ${servicesToSpinUp[@]}
    done
  else
  # Default to spinning all services in specified dockerfiles
    echo "Starting services from dockerfiles"
    for dockerfile in ${dockerfiles[@]}; do

      # rebuild the image to clear cached containers before running containers
      if [[ $build = "1"  ]]; then
        docker-compose -f $dockerfile build
        docker-compose -f $dockerfile stop
        docker-compose -f $dockerfile rm -f
      fi

      docker-compose -f $dockerfile up $detach --force-recreate
    done
  fi
}

# execute the functions to start the docker containers
start
