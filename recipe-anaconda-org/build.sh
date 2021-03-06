#!/bin/bash

set -ex

mkdir -p ./bazel_output_base
export BAZEL_OPTS="--batch --output_base=./bazel_output_base"

# Compile tensorflow from source
export PYTHON_BIN_PATH=${PYTHON}
export PYTHON_LIB_PATH=${SP_DIR}
export CC_OPT_FLAGS="-march=nocona"
# disable jemmloc (needs MADV_HUGEPAGE macro which is not in glib <= 2.12)
export TF_NEED_JEMALLOC=1
export TF_NEED_GCP=0
export TF_NEED_HDFS=0
export TF_ENABLE_XLA=1
export TF_NEED_OPENCL=0
# CUDA details, these should be customized depending on the system details
export TF_NEED_CUDA=1
export TF_CUDA_VERSION="${CUDA_VERSION}"
export TF_CUDNN_VERSION="${CUDNN_VERSION}"
if [ ${CUDNN_VERSION} == "5.1" ]; then
    export TF_CUDNN_VERSION="5"
fi
export TF_CUDA_CLANG=0
# Additional compute capabilities can be added if desired but these increase
# the build time and size of the package. The ones here are the ones supported
# by CUDA 7.5 and used in the devel-gpu tensorflow docker image:
# https://github.com/tensorflow/tensorflow/blob/master/tensorflow/tools/docker/Dockerfile.devel-gpu
# 6.0 and 6.1 should be added with CUDA version 8.0
export TF_CUDA_COMPUTE_CAPABILITIES="3.0,3.5,5.2"
if [ ${CUDA_VERSION} == "8.0" ]; then
    export TF_CUDA_COMPUTE_CAPABILITIES="3.0,3.5,5.2,6.0,6.1"
fi
export GCC_HOST_COMPILER_PATH="/opt/rh/devtoolset-2/root/usr/bin/gcc"
export CUDA_TOOLKIT_PATH="/usr/local/cuda"
export CUDNN_INSTALL_PATH="${PREFIX}"
mkdir -p ${PREFIX}/lib64
cp ${PREFIX}/lib/libcudnn* ${PREFIX}/lib64/
# on ppc64le override some of these parameters
if [ `uname -m`  == ppc64le ]; then
    export CC_OPT_FLAGS=" -mtune=powerpc64le"
    export GCC_HOST_COMPILER_PATH="/usr/bin/gcc"
fi
export TF_NEED_MKL=0
export TF_NEED_VERBS=0
./configure

# build using bazel
# for debugging the following lines may be helpful
#    --logging=6 \
#    --subcommands \
#    --verbose_failures \
bazel ${BAZEL_OPTS} build \
    --config=opt \
    --config=cuda \
    --color=yes \
    --curses=no \
    //tensorflow/tools/pip_package:build_pip_package

# build a whl file
mkdir -p $SRC_DIR/tensorflow_pkg
bazel-bin/tensorflow/tools/pip_package/build_pip_package $SRC_DIR/tensorflow_pkg

# install using pip from the whl file
pip install --no-deps $SRC_DIR/tensorflow_pkg/*.whl

# Run unit tests on the pip installation
# Logic here is based off run_pip_tests.sh in the tensorflow repo
# https://github.com/tensorflow/tensorflow/blob/v1.1.0/tensorflow/tools/ci_build/builds/run_pip_tests.sh
# Note that not all tensorflow tests are run here, only python specific

# tests neeed to be moved into a sub-directory to prevent python from picking
# up the local tensorflow directory
PIP_TEST_PREFIX=bazel_pip
PIP_TEST_ROOT=$(pwd)/${PIP_TEST_PREFIX}
rm -rf $PIP_TEST_ROOT
mkdir -p $PIP_TEST_ROOT
ln -s $(pwd)/tensorflow ${PIP_TEST_ROOT}/tensorflow

# Test which are known to fail on a given platform
KNOWN_FAIL=""

PIP_TEST_FILTER_TAG="-no_pip_gpu,-no_pip"
BAZEL_FLAGS="--define=no_tensorflow_py_deps=true --test_lang_filters=py \
      --build_tests_only -k --test_tag_filters=${PIP_TEST_FILTER_TAG} \
      --test_timeout 9999999"
BAZEL_TEST_TARGETS="${PIP_TEST_PREFIX}/tensorflow/contrib/... \
    ${PIP_TEST_PREFIX}/tensorflow/python/... \
    ${PIP_TEST_PREFIX}/tensorflow/tensorboard/..."
BAZEL_PARALLEL_TEST_FLAGS="--local_test_jobs=1"
# Tests take ~3 hours to run and therefore are skipped in most builds
# These should be run at least once for each new release
#LD_LIBRARY_PATH="/usr/local/nvidia/lib64:/usr/local/cuda/extras/CUPTI/lib64:$LD_LIBRARY_PATH" bazel ${BAZEL_OPTS} test ${BAZEL_FLAGS} \
#    ${BAZEL_PARALLEL_TEST_FLAGS} -- ${BAZEL_TEST_TARGETS} ${KNOWN_FAIL}
rm ${PREFIX}/lib64/libcudnn*
