#!/bin/bash

set -e

source $(dirname $0)/helpers.sh
source /opt/resource/common.sh

it_has_no_url_in_metadata_when_remote_is_not_configured() {
    local repo=$(init_repo)
    local ref=$(make_commit $repo "")
    cd $repo

    test $(git_metadata | jq -r '. | map(select(.name == "url")) | length') = 0
}

it_has_no_url_in_metadata_when_remote_is_not_known() {
    local repo=$(init_repo)
    local ref=$(make_commit $repo "")

    # set an unrecognized origin
    cd $repo
    git remote add origin git@whoknows.com:some/path/repo.git

    test $(git_metadata | jq -r '. | map(select(.name == "url")) | length') = 0
}

it_has_url_in_metadata_when_remote_is_github_scp() {
    local repo=$(init_repo)
    local ref=$(make_commit $repo "")
    local expectedUrl="https://github.com/myorg/myrepo/commit/$ref"

    # set a github origin
    cd $repo
    git remote add origin git@github.com:myorg/myrepo.git

    test $(git_metadata | jq -r '. | map(select(.name == "url")) | length') = 1
    test $(git_metadata | jq -r '.[] | select(.name == "url") | .value') = $expectedUrl

}

it_has_url_in_metadata_when_remote_is_github_ssh() {
    local repo=$(init_repo)
    local ref=$(make_commit $repo "")
    local expectedUrl="https://github.com/myorg/myrepo/commit/$ref"

    # set a github origin
    cd $repo
    git remote add origin ssh://git@github.com/myorg/myrepo.git

    test $(git_metadata | jq -r '. | map(select(.name == "url")) | length') = 1
    test $(git_metadata | jq -r '.[] | select(.name == "url") | .value') = $expectedUrl
}

it_has_url_in_metadata_when_remote_is_github_ssh_over_443() {
    local repo=$(init_repo)
    local ref=$(make_commit $repo "")
    local expectedUrl="https://github.com:443/myorg/myrepo/commit/$ref"

    # set a github origin
    cd $repo
    git remote add origin ssh://git@github.com:443/myorg/myrepo.git

    test $(git_metadata | jq -r '. | map(select(.name == "url")) | length') = 1
    test $(git_metadata | jq -r '.[] | select(.name == "url") | .value') = $expectedUrl
}

it_has_url_in_metadata_when_remote_is_github_https() {
    local repo=$(init_repo)
    local ref=$(make_commit $repo "")
    local expectedUrl="https://github.com/myorg/myrepo/commit/$ref"

    # set a github origin
    cd $repo
    git remote add origin https://github.com/myorg/myrepo.git

    test $(git_metadata | jq -r '. | map(select(.name == "url")) | length') = 1
    test $(git_metadata | jq -r '.[] | select(.name == "url") | .value') = $expectedUrl
}

it_has_url_in_metadata_when_remote_is_likely_github_enterprise() {
    local repo=$(init_repo)
    local ref=$(make_commit $repo "")
    local expectedUrl="https://github.company.com/myorg/myrepo/commit/$ref"

    # set a github enterprise origin
    cd $repo
    git remote add origin https://github.company.com/myorg/myrepo.git

    test $(git_metadata | jq -r '. | map(select(.name == "url")) | length') = 1
    test $(git_metadata | jq -r '.[] | select(.name == "url") | .value') = $expectedUrl
}

it_has_url_in_metadata_when_remote_is_gitlab() {
    local repo=$(init_repo)
    local ref=$(make_commit $repo "")
    local expectedUrl="https://gitlab.com/myorg/mygroup/myrepo/-/commit/$ref"

    # set a gitlab origin with nested groups
    cd $repo
    git remote add origin https://gitlab.com/myorg/mygroup/myrepo.git

    test $(git_metadata | jq -r '. | map(select(.name == "url")) | length') = 1
    test $(git_metadata | jq -r '.[] | select(.name == "url") | .value') = $expectedUrl
}

it_has_url_in_metadata_when_remote_is_bitbucket() {
    local repo=$(init_repo)
    local ref=$(make_commit $repo "")
    local expectedUrl="https://bitbucket.com/myteam/myrepo/commits/$ref"

    # set a bitbucket ssh origin
    cd $repo
    git remote add origin ssh://git@bitbucket.com/myteam/myrepo.git

    test $(git_metadata | jq -r '. | map(select(.name == "url")) | length') = 1
    test $(git_metadata | jq -r '.[] | select(.name == "url") | .value') = $expectedUrl
}

it_truncates_large_messages() {
    local repo=$(init_repo)
    local message=$(cat /dev/urandom | tr -dc A-Z | head -c 20000 ; echo '')
    local ref=$(make_commit $repo $message)
    cd $repo

    test $(git_metadata | jq -r '.[] | select(.name == "message") | .value' | wc -m) = 10241
}

it_creates_github_app_jwt() {
    local client_id="some_client_id"
    local pem=$(get_github_app_private_key)
    local iat="1787583518"
    local exp="1787584178"
    local jwt=$(create_github_app_jwt "$client_id" "$pem" "$iat" "$exp")

    local header_schema='{
        "typ": "",
        "alg": ""
    }'
    local payload_schema='{
        "iat": "",
        "exp": "",
        "iss": ""
    }'

    # extract segments, fix padding, and decode
    local header_json=$(echo -n "$jwt" | cut -d'.' -f1 | sed 's/-/+/g; s/_/\//g' | awk '{ ext = length($0) % 4; if (ext == 2) { print $0 "==" } else if (ext == 3) { print $0 "=" } else { print $0 } }' | base64 -d)
    local payload_json=$(echo -n "$jwt" | cut -d'.' -f2 | sed 's/-/+/g; s/_/\//g' | awk '{ ext = length($0) % 4; if (ext == 2) { print $0 "==" } else if (ext == 3) { print $0 "=" } else { print $0 } }' | base64 -d)

    # validate there are no unknown keys
    local unknown_header_keys=$(echo "$header_schema" "$header_json" | jq --slurp '(.[0] | keys_unsorted) - (.[1] | keys_unsorted)')
    test $(jq -r 'length > 0' <<< $unknown_header_keys) = "false"
    local unknown_payload_keys=$(echo "$payload_schema" "$payload_json" | jq --slurp '(.[0] | keys_unsorted) - (.[1] | keys_unsorted)')
    test $(jq -r 'length > 0' <<< $unknown_payload_keys) = "false"

    # validate expected header values
    test $(jq -r .typ <<< "$header_json") = "JWT"
    test $(jq -r .alg <<< "$header_json") = "RS256"

    # validate expected payload values
    test $(jq -r .iat <<< "$payload_json") = "1787583518"
    test $(jq -r .exp <<< "$payload_json") = "1787584178"
    test $(jq -r .iss <<< "$payload_json") = "some_client_id"

    # keep the signature in base64
    local signature=$(echo -n "$jwt" | cut -d'.' -f3)

    # get the header and payload segments as a single string, we know it has what we expect
    # due to above tests, verify the signature
    local header_and_payload=$(echo -n "$jwt" | cut -d'.' -f1,2)
    local expected_signature=$(openssl dgst -sha256 -sign <(echo -n "${pem}") <(echo -n "${header_and_payload}") | base64 | tr -d '=' | tr '/+' '_-' | tr -d '\n')
    test "$signature" = "$expected_signature"
}

it_gets_github_app_install_id_when_user_set() {
    local base_api_url="https://api.company.ghe.com"
    local jwt="my-jwt"
    local org=""
    local user="company_user"
    local repo=""

    curl() {
      test "$1" = "-s" || return 1
      test "$2" = "-X" || return 1
      test "$3" = "GET" || return 1
      test "$4" = "-H" || return 1
      test "$5" = "Accept: application/vnd.github+json" || return 1
      test "$6" = "-H" || return 1
      test "$7" = "X-GitHub-Api-Version: 2026-03-10" || return 1
      test "$8" = "-H" || return 1
      test "$9" = "Authorization: Bearer my-jwt" || return 1
      test "${10}" = "https://api.company.ghe.com/users/company_user/installation" || return 1

      echo '{"id": 999911}'
    }
    export -f curl
    test $(get_github_app_install_id "$base_api_url" "$jwt" "$org" "$user" "$repo") = 999911
    unset curl
}

it_gets_github_app_install_id_when_org_set() {
    local base_api_url="https://api.something.ghe.com"
    local jwt="fakejwt"
    local org="an_org"
    local user=""
    local repo=""

    curl() {
      test "$1" = "-s" || return 1
      test "$2" = "-X" || return 1
      test "$3" = "GET" || return 1
      test "$4" = "-H" || return 1
      test "$5" = "Accept: application/vnd.github+json" || return 1
      test "$6" = "-H" || return 1
      test "$7" = "X-GitHub-Api-Version: 2026-03-10" || return 1
      test "$8" = "-H" || return 1
      test "$9" = "Authorization: Bearer fakejwt" || return 1
      test "${10}" = "https://api.something.ghe.com/orgs/an_org/installation" || return 1

      echo '{"id": 123456}'
    }
    export -f curl
    test $(get_github_app_install_id "$base_api_url" "$jwt" "$org" "$user" "$repo") = "123456"
    unset curl
}

it_gets_github_app_install_id_when_user_repo_set() {
    local base_api_url="https://api.github.com"
    local jwt="dummyjwt"
    local org=""
    local user="gh_user"
    local repo="a-concourse-resource"

    curl() {
      test "$1" = "-s" || return 1
      test "$2" = "-X" || return 1
      test "$3" = "GET" || return 1
      test "$4" = "-H" || return 1
      test "$5" = "Accept: application/vnd.github+json" || return 1
      test "$6" = "-H" || return 1
      test "$7" = "X-GitHub-Api-Version: 2026-03-10" || return 1
      test "$8" = "-H" || return 1
      test "$9" = "Authorization: Bearer dummyjwt" || return 1
      test "${10}" = "https://api.github.com/repos/gh_user/a-concourse-resource/installation" || return 1

      echo '{"id": 56421}'
    }
    export -f curl
    test $(get_github_app_install_id "$base_api_url" "$jwt" "$org" "$user" "$repo") = "56421"
    unset curl
}

it_gets_github_app_access_token() {
    local base_api_url="https://api.ourcompany.github.com"
    local jwt="some-jwt"
    local install_id="41234"

    curl() {
      test "$1" = "-s" || return 1
      test "$2" = "-X" || return 1
      test "$3" = "POST" || return 1
      test "$4" = "-H" || return 1
      test "$5" = "Accept: application/vnd.github+json" || return 1
      test "$6" = "-H" || return 1
      test "$7" = "X-GitHub-Api-Version: 2026-03-10" || return 1
      test "$8" = "-H" || return 1
      test "$9" = "Authorization: Bearer some-jwt" || return 1
      test "${10}" = "https://api.ourcompany.github.com/app/installations/41234/access_tokens" || return 1

      echo '{"token": "mytoken"}'
    }
    export -f curl
    test $(get_github_app_access_token "$base_api_url" "$jwt" "$install_id") = "mytoken"
    unset curl
}

it_fails_when_github_app_has_invalid_private_key() {
    local input="{
        \"source\": {
            \"uri\": \"https://fakecompany.ghe.com/concourse/git-resource\",
            \"github_app_id\": \"56789\",
            \"github_app_private_key\": \"garbage key\",
            \"github_app_org\": \"some-org\"
        }
    }"
    local err_code=0

    setup_github_app_credentials "${input}" || {
      err_code=1
    }

    test $err_code = 1
}

it_has_no_credential_helper_when_github_app_not_configured() {
      local input="{
          \"source\": {
              \"uri\": \"https://github.com/some-user/some-repo\"
          }
      }"

      setup_github_app_credentials "${input}"

      test -z "$(git config get --global credential.https://github.com.helper || true)"
}

it_has_no_credential_helper_when_github_app_missing_private_key() {
      local input="{
          \"source\": {
              \"uri\": \"https://github.com/some-user/some-repo\",
              \"github_app_id\": \"56789\",
              \"github_app_user\": \"my-user\",
              \"github_app_repo\": \"my-repo\"
          }
      }"

      setup_github_app_credentials "${input}"

      test -z "$(git config get --global credential.https://github.com.helper || true)"
}

it_has_no_credential_helper_when_github_app_missing_app_id() {
      local input="{
          \"source\": {
              \"uri\": \"https://github.com/some-user/some-repo\",
              \"github_app_private_key\": $(get_github_app_private_key_json),
              \"github_app_user\": \"my-user\"
          }
      }"

      setup_github_app_credentials "${input}"

      test -z "$(git config get --global credential.https://github.com.helper || true)"
}

it_has_no_credential_helper_when_github_app_missing_target() {
      local input="{
          \"source\": {
              \"uri\": \"https://github.com/some-user/some-repo\",
              \"github_app_id\": \"99999\",
              \"github_app_private_key\": $(get_github_app_private_key_json)
          }
      }"

      setup_github_app_credentials "${input}"

      test -z "$(git config get --global credential.https://github.com.helper || true)"
}

it_sets_credential_helper_for_org_github_app() {
    local input="{
        \"source\": {
            \"uri\": \"https://fakecompany.ghe.com/concourse/git-resource\",
            \"github_app_id\": \"56789\",
            \"github_app_private_key\": $(get_github_app_private_key_json),
            \"github_app_org\": \"some-org\"
        }
    }"

    create_github_app_jwt() {
      local client_id=$1

      test "$client_id" = "56789" || return 1

      echo "test-jwt"
    }

    get_github_app_install_id() {
      local base_api_url=$1
      local jwt=$2
      local org=$3
      local user=$4
      local repo=$5

      test "$base_api_url" = "https://api.fakecompany.ghe.com" || return 1
      test "$jwt" = "test-jwt" || return 1
      test "$org" = "some-org" || return 1
      test -z "${user}" || return 1
      test -z "${repo}" || return 1

      echo "95432"
    }

    get_github_app_access_token()  {
      local base_api_url=$1
      local jwt=$2
      local install_id=$3

      test "$base_api_url" = "https://api.fakecompany.ghe.com" || return 1
      test "$jwt" = "test-jwt" || return 1
      test "$install_id" = "95432" || return 1

      echo "a-token"
    }

    export -f create_github_app_jwt get_github_app_install_id get_github_app_access_token
    setup_github_app_credentials "${input}"

    test "$(git config get --global credential.https://fakecompany.ghe.com.helper)" = "!f() { echo \"username=x-access-token\"; echo \"password=a-token\"; }; f"

    # clean up tests
    unset create_github_app_jwt get_github_app_install_id get_github_app_access_token
    git config unset --global credential.https://fakecompany.ghe.com.helper
}

it_sets_credential_helper_for_user_github_app() {
    local input="{
        \"source\": {
            \"uri\": \"https://github.com/test-user/test-repo\",
            \"github_app_id\": \"99999\",
            \"github_app_private_key\": $(get_github_app_private_key_json),
            \"github_app_user\": \"the-user\"
        }
    }"

    create_github_app_jwt() {
      local client_id=$1

      test "$client_id" = "99999" || return 1

      echo "test-jwt2"
    }

    get_github_app_install_id() {
      local base_api_url=$1
      local jwt=$2
      local org=$3
      local user=$4
      local repo=$5

      test "$base_api_url" = "https://api.github.com" || return 1
      test "$jwt" = "test-jwt2" || return 1
      test -z "$org" || return 1
      test "$user" = "the-user" || return 1
      test -z "$repo" || return 1

      echo "555555"
    }

    get_github_app_access_token()  {
      local base_api_url=$1
      local jwt=$2
      local install_id=$3

      test "$base_api_url" = "https://api.github.com" || return 1
      test "$jwt" = "test-jwt2" || return 1
      test "$install_id" = "555555" || return 1

      echo "a-token2"
    }

    export -f create_github_app_jwt get_github_app_install_id get_github_app_access_token
    setup_github_app_credentials "${input}"

    test "$(git config get --global credential.https://github.com.helper)" = "!f() { echo \"username=x-access-token\"; echo \"password=a-token2\"; }; f"

    # clean up tests
    unset create_github_app_jwt get_github_app_install_id get_github_app_access_token
    git config unset --global credential.https://github.com.helper
}

it_sets_credential_helper_for_repo_github_app() {
    local input="{
        \"source\": {
            \"uri\": \"https://mycompany.ghe.com/test-user/test-repo\",
            \"github_app_id\": \"90210\",
            \"github_app_private_key\": $(get_github_app_private_key_json),
            \"github_app_user\": \"the-user\",
            \"github_app_repo\": \"the-repo\"
        }
    }"

    create_github_app_jwt() {
      local client_id=$1

      test "$client_id" = "90210" || return 1

      echo "test-jwt3"
    }

    get_github_app_install_id() {
      local base_api_url=$1
      local jwt=$2
      local org=$3
      local user=$4
      local repo=$5

      test "$base_api_url" = "https://api.mycompany.ghe.com" || return 1
      test "$jwt" = "test-jwt3" || return 1
      test -z "$org" || return 1
      test "$user" = "the-user" || return 1
      test "$repo" = "the-repo" || return 1

      echo "111111"
    }

    get_github_app_access_token()  {
      local base_api_url=$1
      local jwt=$2
      local install_id=$3

      test "$base_api_url" = "https://api.mycompany.ghe.com" || return 1
      test "$jwt" = "test-jwt3" || return 1
      test "$install_id" = "111111" || return 1

      echo "a-token3"
    }

    export -f create_github_app_jwt get_github_app_install_id get_github_app_access_token
    setup_github_app_credentials "${input}"

    test "$(git config get --global credential.https://mycompany.ghe.com.helper)" = "!f() { echo \"username=x-access-token\"; echo \"password=a-token3\"; }; f"

    # clean up tests
    unset create_github_app_jwt get_github_app_install_id get_github_app_access_token
    git config unset --global credential.https://mycompany.ghe.com.helper
}

run it_has_no_url_in_metadata_when_remote_is_not_configured
run it_has_no_url_in_metadata_when_remote_is_not_known

run it_has_url_in_metadata_when_remote_is_github_scp
run it_has_url_in_metadata_when_remote_is_github_ssh
run it_has_url_in_metadata_when_remote_is_github_ssh_over_443
run it_has_url_in_metadata_when_remote_is_github_https
run it_has_url_in_metadata_when_remote_is_likely_github_enterprise

run it_has_url_in_metadata_when_remote_is_gitlab
run it_has_url_in_metadata_when_remote_is_bitbucket
run it_truncates_large_messages

run it_creates_github_app_jwt
run it_gets_github_app_install_id_when_user_set
run it_gets_github_app_install_id_when_org_set
run it_gets_github_app_install_id_when_user_repo_set
run it_gets_github_app_access_token
run it_fails_when_github_app_has_invalid_private_key
run it_has_no_credential_helper_when_github_app_not_configured
run it_has_no_credential_helper_when_github_app_missing_private_key
run it_has_no_credential_helper_when_github_app_missing_app_id
run it_has_no_credential_helper_when_github_app_missing_target
run it_sets_credential_helper_for_org_github_app
run it_sets_credential_helper_for_user_github_app
run it_sets_credential_helper_for_repo_github_app
