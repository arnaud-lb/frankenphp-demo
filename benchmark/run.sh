#!/bin/bash

export LC_ALL=C
set -e
set -x

variants=(bookworm alpine alpine-noupx alpine-noupx-jemalloc alpine-noupx-mimalloc)

(
    if ! [ -d frankenphp ]; then
        git clone https://github.com/arnaud-lb/frankenphp --depth 1 --branch musl-benchmark
    fi
    cd frankenphp
    git reset --hard
    git clean -dfx
    git pull
    sudo docker buildx bake --load --set '*.platform=linux/amd64' runner-php-8-3-bookworm-yes runner-php-8-3-alpine-yes runner-php-8-3-alpine-no
)

for variant in "${variants[@]}"; do
    printf "Benchmarking variant: %s\n" "$variant"

    sudo docker rm --force FrankenPHP-demo >/dev/null 2>&1 || true

    tag="dev-php8.3-$variant"

    _LD_PRELOAD=
    if [[ "$tag" =~ jemalloc ]]; then
        _LD_PRELOAD="-e LD_PRELOAD=/usr/lib/libjemalloc.so.2"
        tag=${tag/-jemalloc/}
        if ! sudo docker run --rm \
                $_LD_PRELOAD \
                "dunglas/frankenphp:${tag}" \
                env MALLOC_CONF=confirm_conf:true /usr/local/bin/frankenphp 2>&1 \
                | grep -q 'value of the environment variable MALLOC_CONF'; then
            printf "%s is ignored" "$_LD_PRELOAD" >&2
            exit 1
        fi
    elif [[ "$tag" =~ mimalloc ]]; then
        _LD_PRELOAD="-e LD_PRELOAD=/usr/lib/libmimalloc.so.2"
        tag=${tag/-mimalloc/}
        if ! sudo docker run --rm \
                $_LD_PRELOAD \
                "dunglas/frankenphp:${tag}" \
                env MIMALLOC_VERBOSE=1 /usr/local/bin/frankenphp 2>&1 \
                | grep -q 'mimalloc:'; then
            printf "%s is ignored" "$_LD_PRELOAD" >&2
            exit 1
        fi
    fi

    sudo docker run \
        --rm \
        -d \
        -e FRANKENPHP_CONFIG="worker ./public/index.php" \
        $_LD_PRELOAD \
        -v $PWD/..:/app \
        -p 80:80 -p 443:443/tcp -p 443:443/udp \
        --name FrankenPHP-demo \
        "dunglas/frankenphp:${tag}"

    ok=
    for i in $(seq 1 10); do
        if sudo docker exec -it FrankenPHP-demo php bin/console doctrine:migrations:migrate --no-interaction; then
            ok=1
            break
        fi
        sleep 1
    done

    if [ -z "$ok" ]; then
        echo "Failed"
    fi

    echo "Warmup"
    k6 run  --insecure-skip-tls-verify -u 100 -d 10s script.js >/dev/null
    echo "Benchmark"
    k6 run  --summary-export "out.$variant" --insecure-skip-tls-verify -u 100 -d 30s script.js >/dev/null
done

sudo docker rm --force FrankenPHP-demo || true

base="$(cat "out.${variants[0]}" | jq '.metrics.http_req_duration.avg')"

set +x
for variant in "${variants[@]}"; do
    (
        echo "$variant"
        cat out.$variant | jq --arg base "$base" '.metrics.http_req_duration.avg, (.metrics.http_req_duration.avg-($base|tonumber))*100/($base|tonumber)'
    ) | xargs printf "%s: %.f +%.02f%%\n"
done | column -t

