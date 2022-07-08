#!/bin/bash
#
# Dscription: Script for calculating Semantic Versions for tagged mono-repositories.
#
# This script assumes that all tags are in the format "domain-v1.0.0". Version numbers are calculated
# by fetching the previous tag, parsing it and incrementing the major, minor or patch values. 
#
# @author Brian Cowdery
# @since 31-Mar-2022
# colors
red='\e[1;31m%s\e[0m'
green='\e[1;32m%s\e[0m'
yellow='\e[1;33m%s\e[0m'
help()
{
    echo "Calculates version numbers for services in a mono-repository."
    echo 
    echo "Syntax: $(basename $0) -p <prefix> -b <branch_name> -j"
    echo "Options:"
    echo "-p              Git tag prefix for the micro-service."
    echo "-b              Git branch name (optional)."
    echo "-i              Specifiy the SemVer token to increment (optional)."
    echo "-j              Format the results as JSON (optional)."
    echo
    echo "Environment variables:"
    echo "CI              Boolean true/false flag indicates when this script is running on a build server; prints github output vars when true."
    echo "GIT_SHA         Git SHA hash. Defaults to the current HEAD." 
    echo "GIT_BRANCH      Git branch name. Defaults to the current HEAD."
    echo "GIT_TAG_PREFIX  Git tag prefix for the micro-service."
    echo
    echo "Examples: "
    echo "    ./$(basename $0) -p campaign-v"
    echo "    GIT_TAG_PREFIX=\"campaign-v\" GIT_BRANCH=\"feature/foo\" ./$(basename $0)"
}
while getopts ":hp:b:i:j" option; do
    case $option in
        h) # display help
            help
            exit;;
        
        p) # set version prefix
            GIT_TAG_PREFIX="${OPTARG}"
            ;;
        b) # set branch name
            GIT_BRANCH="${OPTARG}"
            ;;
        j) # set json output
            JSON=true
            ;;
        i) # set version increment
            INCREMENT="${OPTARG}"
            ;;
        \?) # Invalid option
            echo "Error: Invalid option, -h to show help."
            exit;;
    esac
done
# Use github provided environment varaibles when building PRs
# These are more acurate than attempting to parse the revision history in PR merge branches
if [[ -z "${GIT_SHA-}" ]]; then
    if [[ -z "${GITHUB_SHA-}" ]]; then
        GIT_SHA=$(git rev-parse HEAD)
    else        
        GIT_SHA=$GITHUB_SHA
    fi
fi
if [[ -z "${GIT_BRANCH-}" ]]; then
    if [[ -z "${GITHUB_HEAD_REF-}" ]]; then
        GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
    else
        GIT_BRANCH=$GITHUB_HEAD_REF
    fi
fi
if [[ -z "${GIT_BRANCH-}" ]]; then
    echo "Error: Branch name -b, or the GIT_BRANCH environment variable is required."
    exit 1
fi
if [[ -z "${GIT_TAG_PREFIX-}" ]]; then
    echo "Error: Version tag prefix -p, or the GIT_TAG_PREFIX environment variable is required."
    exit 1
fi
main() 
{
    local lasttag=$(git describe --tags --match "${GIT_TAG_PREFIX}*" --abbrev=0)
    local latest=(${lasttag/$GIT_TAG_PREFIX/})
    echo "Sha: $GIT_SHA"
    echo "Branch: $GIT_BRANCH" 
    echo "Prefix: $GIT_TAG_PREFIX"
    echo "Last tag: $lasttag"
    echo "Last version: $latest"
    echo
    # parse branch name for pre-release tags
    # set incrementation type based on the branch. 
    local increment="${INCREMENT}"
    local branchlabel="${GIT_BRANCH}"
    local prerelease=""
    local suffix=""
    local count=0
    # strip separator characters and the fetature/ prefix
    branchlabel=(${branchlabel/feature\//})
    branchlabel=(${branchlabel//\//})
    branchlabel=(${branchlabel//-/})
    branchlabel=(${branchlabel//_/})
    # count number of commits since last tag
    if [[ "$lasttag" != "" ]]; then
        count=$(git rev-list HEAD ^${lasttag} --ancestry-path ${lasttag} --count)
    fi
    # parse the branch name and determine
    # pre-release labels and the version number token we should increment
    if [[ $increment == "" ]]; then
        case $GIT_BRANCH in
            main)
                increment="MINOR"
                ;;
            release/*)
                prerelease="-hotfix"
                increment="PATCH"
                ;;
            hotfix/*)
                prerelease=$"-${branchlabel}"
                suffix=".${count}"
                increment="PATCH"
                ;;            
            *)
                # all other branches (feature/ chore/ fix/ etc)
                # if its not main, treat it as a feature branch
                prerelease=$"-${branchlabel}"
                suffix=".${count}"
                increment="MINOR"
                ;;
        esac
    fi
    # Test if the commit we're building is already tagged, and do not increment when we're building the exact tagged commit.
    # Test if we're building a branch new service without any existing tags. Default to 1.0.0.
    if [[ "$lasttag" != "" ]]; then
        
        local tagref=$(git show-ref --hash --tags $lasttag)
        if [[ "$tagref" == "$GIT_SHA" ]]; then
            printf "$green\n" "Commit ref $GIT_SHA is already tagged as $lasttag, skipping $increment increment."
            increment="NONE"
        else
            printf "$yellow\n" "Commit ref $GIT_SHA is not tagged. Incrementing $increment."
        fi
    else
        printf "$yellow\n" "Last tag not found, defaulting version to 1.0.0."
        increment="NONE"
    fi
    # increment semver
    # defaults to 1.0.0 if no last tag found
    local version=""
    local semver_parts=(${latest//./ })
    local major=${semver_parts[0]:-1} 
    local minor=${semver_parts[1]:-0}
    local patch=${semver_parts[2]:-0}
    case $increment in
        MAJOR) 
            major=$((major+1))
            minor=0
            patch=0
            ;;
        MINOR)
            minor=$((minor+1))
            patch=0
            ;;
        PATCH)
            patch=$((patch+1))
            ;;
        NONE)
            ;;
        *) 
            echo "Error: Invalid version increment option, -h to show help."
            exit
            ;;
    esac
    # output
    # build version numbers
    version=${major}.${minor}.${patch}
    local tag="${GIT_TAG_PREFIX}${version}"
    local semver="${version}${prerelease}${suffix}"
    local informationalversion="${version}${prerelease}${suffix}+Branch.${GIT_BRANCH//\//-}.Sha.${GIT_SHA}"
    # github action runner output vars
    if [[ $CI == "true" ]]; then
        echo
        echo "::set-output name=major::$major"
        echo "::set-output name=minor::$minor"
        echo "::set-output name=patch::$patch"
        echo "::set-output name=prerelease::$prerelease$suffix"
        echo "::set-output name=sha::$GIT_SHA"
        echo "::set-output name=tag::$tag"
        echo "::set-output name=semVer::$semver"
        echo "::set-output name=informationalVersion::$informationalversion"
    fi
    # format results as JSON 
    if [[ $JSON == "true" || $CI == "true" ]]; then
        JSON=$(jq --null-input \
            --arg major "$major" \
            --arg minor "$minor" \
            --arg patch "$patch" \
            --arg prerelease "$prerelease$suffix" \
            --arg sha "$GIT_SHA" \
            --arg tag "$tag" \
            --arg nexttag "$nexttag" \
            --arg semver "$semver" \
            --arg infover "$informationalversion" \
            '{"major":$major, "minor":$minor, "patch":$patch, "prerelease":$prerelease, "sha":$sha, "tag":$tag, "semVer":$semver, "informationalVersion":$infover}'
        )
        echo
        echo "$JSON"
    else
        echo 
        echo "$semver"
    fi
}
main
