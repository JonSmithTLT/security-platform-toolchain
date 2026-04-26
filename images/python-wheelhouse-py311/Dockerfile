# images/python-wheelhouse-py311/Dockerfile
# Frozen CPython 3.11 Linux x86_64 wheelhouse artifact image.
# This is a data carrier, not a runtime base image.
# Extract wheels with:
#   id=$(docker create spt-python-wheelhouse-py311:TAG)
#   docker cp "${id}:/wheelhouse/." ./local-wheels/
#   docker rm "${id}"

FROM busybox

LABEL org.opencontainers.image.description="SPT frozen CPython 3.11 Linux x86_64 wheelhouse artifact"

COPY data-bundles/sources/python-wheels/py311/ /wheelhouse/py311/
COPY requirements/py311/                       /requirements/py311/

CMD ["find", "/wheelhouse/py311", "-name", "*.whl", "-printf", "%f\n"]
