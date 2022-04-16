#!/bin/bash

set -eux

CRATE_NAME="$1"
VERSION_PART="$2"
GIT_EMAIL="$3"

declare -a GIT_TAGS
declare -a CRATES

function git_set_tags(){
  git config user.name "robot"
  git config user.email "$GIT_EMAIL"

  git commit -am "bump version for $CRATE_NAME, $VERSION_PART"

  local GIT_TAG
  for GIT_TAG in "${GIT_TAGS[@]}";  do
    git tag "$GIT_TAG"
  done
}

function publish_crate() {
    local CRATE_NAME="$1"
    (
      cd "$CRATE_NAME"

      local SUCCESS=0
      for TRY_COUNTER in $(seq 0 10); do
        [ "$TRY_COUNTER" != "0" ] && echo "retry count: $TRY_COUNTER" && sleep 60

        if cargo publish; then
          SUCCESS=1
          break
        fi
      done

      if [ "$SUCCESS" == "0" ]; then
        echo "Publish crate '$CRATE_NAME' failed."
        return 1
      fi
    )
}

function version_get() {
  local CRATE_NAME="$1"
  local VERSION_LINE VERSION

  VERSION_LINE="$(grep "^version\\s*=" "$CRATE_NAME/Cargo.toml")"
  VERSION=$(echo "$VERSION_LINE" | cut -d '"' -f 2)
  echo "$VERSION"
}

function version_increment()
{
  local VERSION UP_PART VERSION_MAJOR VERSION_MINOR VERSION_PATCH

  VERSION="$1"
  UP_PART="$2"
  VERSION_MAJOR=$(echo "$VERSION" | cut -d '.' -f 1)
  VERSION_MINOR=$(echo "$VERSION" | cut -d '.' -f 2)
  VERSION_PATCH=$(echo "$VERSION" | cut -d '.' -f 3)

  case "$UP_PART" in
    major)
      VERSION_MAJOR=$((VERSION_MAJOR+1))
      VERSION_MINOR=0
      VERSION_MINOR=0
      ;;
    minor)
      VERSION_MINOR=$((VERSION_MINOR+1))
      VERSION_PATCH=0
      ;;
    patch)
      VERSION_PATCH=$((VERSION_PATCH+1))
  esac

  echo "$VERSION_MAJOR.$VERSION_MINOR.$VERSION_PATCH"
}

function version_set() {
  local CRATE_NAME="$1"
  local VERSION="$2"

  sed -i.bak -e "s/^version *=.*/version = \"$VERSION\"/" "$CRATE_NAME/Cargo.toml"
}

function version_dep_set() {
  local CRATE_NAME="$1"
  local DEP_NAME="$2"
  local VERSION="$3"

  sed -i.bak -e "s|^$DEP_NAME *=.*|$DEP_NAME = \\{ version = \"$VERSION\", path=\"../$DEP_NAME\"\\}|" "$CRATE_NAME/Cargo.toml"
}

function bump_version() {
  local CRATE_NAME="$1"
  local VERSION_PART="$2"

  local VERSION
  VERSION=$(version_get "$CRATE_NAME")
  VERSION=$(version_increment "$VERSION" "$VERSION_PART")
  version_set "$CRATE_NAME" "$VERSION"
  GIT_TAGS+=("$CRATE_NAME-$VERSION")
  CRATES+=("$CRATE_NAME")

  case "$CRATE_NAME" in
    ydb)
      ;;
    ydb-grpc)
      version_dep_set "ydb" "ydb-grpc" "$VERSION"
      bump_version "ydb" patch
      ;;
    ydb-grpc-helpers)
      version_dep_set "ydb-grpc" "ydb-grpc-helpers" "$VERSION"
      bump_version "ydb-grpc" patch
      ;;
    *)
      echo "Unexpected crate name '$CRATE_NAME'"
      exit 1
  esac
}

bump_version "$CRATE_NAME" "$VERSION_PART"

# Force update Cargo.toml for new versions
cargo check
echo 123
git_set_tags

# push tags before publish - for fix repository state if failed in middle of publish crates
git push --tags

for CRATE in "${CRATES[@]}"; do
  publish_crate "$CRATE"
done

# git push after publish crate - for run CI build check after all changed crates will published in crates repo
git push
