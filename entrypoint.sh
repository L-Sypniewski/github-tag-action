#!/bin/bash

set -o pipefail

# config
default_semvar_bump=${DEFAULT_BUMP:-minor}
prefix=${PREFIX}
release_branches=${RELEASE_BRANCHES:-master}
custom_tag=${CUSTOM_TAG}
source=${SOURCE:-.}
dryrun=${DRY_RUN:-false}
initial_version=${INITIAL_VERSION:-0.0.0}
tag_context=${TAG_CONTEXT:-repo}
suffix=${PRERELEASE_SUFFIX:-beta}
verbose=${VERBOSE:-true}

cd ${GITHUB_WORKSPACE}/${source}

echo "*** CONFIGURATION ***"
echo -e "\tDEFAULT_BUMP: ${default_semvar_bump}"
echo -e "\tPREFIX: ${prefix}"
echo -e "\tRELEASE_BRANCHES: ${release_branches}"
echo -e "\tCUSTOM_TAG: ${custom_tag}"
echo -e "\tSOURCE: ${source}"
echo -e "\tDRY_RUN: ${dryrun}"
echo -e "\tINITIAL_VERSION: ${initial_version}"
echo -e "\tTAG_CONTEXT: ${tag_context}"
echo -e "\tPRERELEASE_SUFFIX: ${suffix}"
echo -e "\tVERBOSE: ${verbose}"

current_branch=$(git rev-parse --abbrev-ref HEAD)

pre_release="true"
IFS=',' read -ra branch <<< "$release_branches"
for b in "${branch[@]}"; do
    echo "Is $b a match for ${current_branch}"
    if [[ "${current_branch}" =~ $b ]]
    then
        pre_release="false"
    fi
done
echo "pre_release = $pre_release"

# fetch tags
git fetch --tags

# get latest tag that looks like a semver (with or without v)
case "$tag_context" in
    *repo*) 
        tag=$(git for-each-ref --sort=-v:refname --format '%(refname)' | cut -d / -f 3- | grep -E "^($prefix)?[0-9]+.[0-9]+.[0-9]+$" | head -n1)
        pre_tag=$(git for-each-ref --sort=-v:refname --format '%(refname)' | cut -d / -f 3- | grep -E "^($prefix)?[0-9]+.[0-9]+.[0-9]+(-$suffix.[0-9]+)?$" | head -n1)
        ;;
    *branch*) 
        tag=$(git tag --list --merged HEAD --sort=-v:refname | grep -E "^($prefix)?[0-9]+.[0-9]+.[0-9]+$" | head -n1)
        pre_tag=$(git tag --list --merged HEAD --sort=-v:refname | grep -E "^($prefix)?[0-9]+.[0-9]+.[0-9]+(-$suffix.[0-9]+)?$" | head -n1)
        ;;
    * ) echo "Unrecognised context"; exit 1;;
esac

# if there are none, start tags at INITIAL_VERSION which defaults to 0.0.0
if [ -z "$tag" ]
then
    log=$(git log --pretty='%B')
    tag="$initial_version"
    pre_tag="$initial_version"
else
    log=$(git log $tag..HEAD --pretty='%B')
fi

# get current commit hash for tag
tag_commit=$(git rev-list -n 1 $tag)

# get current commit hash
commit=$(git rev-parse HEAD)

if [ "$tag_commit" == "$commit" ]; then
    echo "No new commits since previous tag. Skipping..."
    echo ::set-output name=tag::$tag
    exit 0
fi

# echo log if verbose is wanted
if $verbose
then
  echo $log
fi

# calculate new tag

    # Get number of occurrences of bump key words in 
    # all commits between the current one and the last tag

if [ $tag = $initial_version ]; then

    echo "Tag is equal to initial version"
    number_of_major=$(git log --pretty=format:%B | grep -E "#major" -c)
    number_of_minor=$(git log --pretty=format:%B | grep -E "#minor" -c)
    number_of_patch=$(git log --pretty=format:%B | grep -E "#patch" -c)
else 

    echo -e "Tag is not equal to initial version"
    echo -e "\tCurrent commit: ${commit}\n\tlast tag: ${tag}"
    echo -e "Latest commits:"
    echo -e "\t$(git log $commit...$tag --pretty=format:%B)"
    echo -e "**************************"

    number_of_major=$(git log $commit...$tag --pretty=format:%B | grep -E "#major" -c)
    number_of_minor=$(git log $commit...$tag --pretty=format:%B | grep -E "#minor" -c)
    number_of_patch=$(git log $commit...$tag --pretty=format:%B | grep -E "#patch" -c)
fi


tagWithoutPrefix=${tag#"$prefix"}

if $verbose
then
  echo "number_of_major occurrences ${number_of_major}"
  echo "number_of_minor occurrences ${number_of_minor}"
  echo "number_of_patch occurrences ${number_of_patch}"
  echo "tagWithoutPrefix ${tagWithoutPrefix}"
fi


if [ $number_of_major = 0 ] & [ $number_of_minor = 0 ]; then
    for (( c=1; c<=$number_of_patch; c++ ))
    do
        new=$(semver -i patch $tagWithoutPrefix); part="patch"
    done
fi

if [ $number_of_major = 0 ]; then
    for (( c=1; c<=$number_of_minor; c++ ))
    do
        new=$(semver -i minor $tagWithoutPrefix); part="minor"
    done
fi

for (( c=1; c<=$number_of_major; c++ ))
    do
        new=$(semver -i major $tagWithoutPrefix); part="major"
    done

if [ $number_of_major = 0 ] & [ $number_of_minor = 0 ] & [ $number_of_patch = 0 ]; then
    if [ "$default_semvar_bump" == "none" ]; then
            echo "Default bump was set to none. Skipping..."; exit 0 
    else 
            new=$(semver -i "${default_semvar_bump}" $tagWithoutPrefix); part=$default_semvar_bump 
    fi 
fi

#temp
echo -e "\nNew tag: $new"
exit 0
#**

if $pre_release
then
    # Already a prerelease available, bump it
    if [[ "$pre_tag" == *"$new"* ]]; then
        new=$(semver -i prerelease $pre_tag --preid $suffix); part="pre-$part"
    else
        new="$new-$suffix.1"; part="pre-$part"
    fi
fi

echo $part

# did we get a new tag?
if [ ! -z "$new" ]
then
	# prefix with 'prefix'
	if [ ! -z "$prefix" ]
	then
		new="$prefix$new"
	fi
fi

# set a new tag to a provider CUSTOM_TAG - discard calculated tag
if [ ! -z $custom_tag ]
then
    new="$custom_tag"
fi

if $pre_release
then
    echo -e "Bumping tag ${pre_tag}. \n\tNew tag ${new}"
else
    echo -e "Bumping tag ${tag}. \n\tNew tag ${new}"
fi

# set outputs
new_tag_without_prefix=${new#"$prefix"}
echo "New tag without prefix: $new_tag_without_prefix"
echo "Prefix: $prefix"
echo "new_tag: $new_tag"

echo ::set-output name=new_tag::$new
echo ::set-output name=new_tag_without_prefix::$new_tag_without_prefix
echo ::set-output name=part::$part

# set the old tag value as an output
echo ::set-output name=tag::$tag


# use dry run to determine the next tag
if $dryrun
then
    exit 0
fi 


# create local git tag
git tag $new

# push new tag ref to github
dt=$(date '+%Y-%m-%dT%H:%M:%SZ')
full_name=$GITHUB_REPOSITORY
git_refs_url=$(jq .repository.git_refs_url $GITHUB_EVENT_PATH | tr -d '"' | sed 's/{\/sha}//g')

echo "$dt: **pushing tag $new to repo $full_name"

git_refs_response=$(
curl -s -X POST $git_refs_url \
-H "Authorization: token $GITHUB_TOKEN" \
-d @- << EOF

{
  "ref": "refs/tags/$new",
  "sha": "$commit"
}
EOF
)

git_ref_posted=$( echo "${git_refs_response}" | jq .ref | tr -d '"' )

echo "::debug::${git_refs_response}"
if [ "${git_ref_posted}" = "refs/tags/${new}" ]; then
  exit 0
else
  echo "::error::Tag was not created properly."
  exit 1
fi
