# ctest --extra-verbose --no-compress-output --output-on-failure
#
# Variables:
#
#   ENV{BUILD_ID}         optional    value of Jenkins BUILD_ID
#   ENV{WORKSPACE}        required    value of Jenkins WORKSPACE
#
#   ENV{compiler}         optional    "clang" | "gcc"
#   ENV{coverage}         optional    boolean
#   ENV{debug}            optional    boolean
#   ENV{ghprbPullId}      optional    value for CTEST_CHANGE_ID
#   ENV{matlab}           optional    boolean
#   ENV{openSource}       optional    boolean
#   ENV{track}            optional    "continuous" | "experimental" | "nightly"
#
#   buildname             optional    value for CTEST_BUILD_NAME
#   site                  optional    value for CTEST_SITE

cmake_minimum_required(VERSION 3.6 FATAL_ERROR)

set(COVERAGE $ENV{coverage})
set(DEBUG $ENV{debug})
set(MATLAB $ENV{matlab})
set(OPEN_SOURCE $ENV{openSource})
set(TRACK $ENV{track})

if(NOT DEFINED ENV{WORKSPACE})
  message(FATAL_ERROR
    "*** CTest Result: FAILURE BECAUSE ENV{WORKSPACE} WAS NOT SET")
endif()

file(TO_CMAKE_PATH "$ENV{WORKSPACE}" DASHBOARD_WORKSPACE)

if(NOT TRACK)
  set(TRACK "experimental")
endif()

# set site and build name
if(DEFINED site)
  string(REGEX REPLACE "(.*) (.*)" "\\1" DASHBOARD_SITE "${site}")
  set(CTEST_SITE "${DASHBOARD_SITE}")
else()
  message(WARNING "*** CTEST_SITE was not set")
endif()

if(DEFINED buildname)
  set(CTEST_BUILD_NAME "${buildname}")
  if(TRACK STREQUAL "experimental")
    if(DEBUG)
      set(CTEST_BUILD_NAME "${CTEST_BUILD_NAME}-debug")
    else()
      set(CTEST_BUILD_NAME "${CTEST_BUILD_NAME}-release")
    endif()
  endif()
  if(DEFINED ENV{ghprbPullId})
    set(CTEST_BUILD_NAME "${CTEST_BUILD_NAME}-$ENV{ghprbPullId}")
  endif()
else()
  message(WARNING "*** CTEST_BUILD_NAME was not set")
endif()

include(ProcessorCount)
ProcessorCount(DASHBOARD_PROCESSOR_COUNT)

set(CTEST_TEST_ARGS "")

if(DASHBOARD_PROCESSOR_COUNT EQUAL 0)
  message(WARNING "*** CTEST_TEST_ARGS PARALLEL_LEVEL was not set")
else()
  set(CTEST_TEST_ARGS ${CTEST_TEST_ARGS}
    PARALLEL_LEVEL ${DASHBOARD_PROCESSOR_COUNT})
endif()

if(NOT DEFINED ENV{compiler})
  message(WARNING "*** ENV{compiler} was not set")
  set(COMPILER "gcc")
else()
  set(COMPILER $ENV{compiler})
endif()

# check for compiler settings
if(COMPILER STREQUAL "gcc")
  set(ENV{CC} "gcc-4.9")
  set(ENV{CXX} "g++-4.9")
elseif(COMPILER STREQUAL "clang")
  set(ENV{CC} "clang")
  set(ENV{CXX} "clang++")
endif()

set(ENV{F77} "gfortran-4.9")
set(ENV{FC} "gfortran-4.9")

if(MATLAB)
  set(ENV{PATH} "/usr/local/MATLAB/R2015b/bin:$ENV{PATH}")
endif()

# Set ROS Environment Up (Equivalent to sourcing /opt/ros/indigo/setup.bash)
set(ENV{ROS_ROOT} "/opt/ros/indigo/share/ros")
set(ENV{ROS_PACKAGE_PATH} "/opt/ros/indigo/share:/opt/ros/indigo/stacks")
set(ENV{ROS_MASTER_URI} "http://localhost:11311")
set(ENV{LD_LIBRARY_PATH} "/opt/ros/indigo/lib:$ENV{LD_LIBRARY_PATH}")
set(ENV{CPATH} "/opt/ros/indigo/include:$ENV{CPATH}")
set(ENV{PATH} "/opt/ros/indigo/bin:$ENV{PATH}")
set(ENV{ROSLISP_PACKAGE_DIRECTORIES} "")
set(ENV{ROS_DISTRO} "indigo")
set(ENV{PYTHONPATH} "/opt/ros/indigo/lib/python2.7/dist-packages:$ENV{PYTHONPATH}")
set(ENV{PKG_CONFIG_PATH} "/opt/ros/indigo/lib/pkgconfig:$ENV{PKG_CONFIG_PATH}")
set(ENV{CMAKE_PREFIX_PATH} "/opt/ros/indigo")
set(ENV{ROS_ETC_DIR} "/opt/ros/indigo/etc/ros")
set(ENV{ROS_HOME} "${DASHBOARD_WORKSPACE}")

# Set TERM to dumb to work around tput errors from catkin-tools
# https://github.com/catkin/catkin_tools/issues/157#issuecomment-221975716
set(ENV{TERM} "dumb")

set(CTEST_GIT_COMMAND "git")
set(CTEST_UPDATE_COMMAND "${CTEST_GIT_COMMAND}")
set(CTEST_UPDATE_VERSION_ONLY ON)

if(NOT OPEN_SOURCE)
  execute_process(COMMAND mktemp -q /tmp/id_rsa_XXXXXXXX
    RESULT_VARIABLE DASHBOARD_MKTEMP_RESULT_VARIABLE
    OUTPUT_VARIABLE DASHBOARD_MKTEMP_OUTPUT_VARIABLE)
  if(NOT DASHBOARD_MKTEMP_RESULT_VARIABLE EQUAL 0)
    file(WRITE "${DASHBOARD_WORKSPACE}/FAILURE")
    message(FATAL_ERROR
      "*** CTest Result: FAILURE BECAUSE CREATION OF TEMPORARY IDENTITY FILE WAS NOT SUCCESSFUL")
  endif()
  set(DASHBOARD_SSH_IDENTITY_FILE "${DASHBOARD_MKTEMP_OUTPUT_VARIABLE}")
  find_program(DASHBOARD_AWS_COMMAND NAMES "aws")
  if(NOT DASHBOARD_AWS_COMMAND)
    file(WRITE "${DASHBOARD_WORKSPACE}/FAILURE")
    message(FATAL_ERROR "*** CTest Result: FAILURE BECAUSE AWS WAS NOT FOUND")
  endif()
  execute_process(COMMAND ${DASHBOARD_AWS_COMMAND} s3 cp s3://drake-provisioning/id_rsa "${DASHBOARD_SSH_IDENTITY_FILE}"
    RESULT_VARIABLE DASHBOARD_AWS_S3_RESULT_VARIABLE)
  if(NOT DASHBOARD_AWS_S3_RESULT_VARIABLE EQUAL 0)
    file(WRITE "${DASHBOARD_WORKSPACE}/FAILURE")
    message(FATAL_ERROR
      "*** CTest Result: FAILURE BECAUSE DOWNLOAD OF IDENTITY FILE FROM AWS S3 WAS NOT SUCCESSFUL")
  endif()
  file(SHA1 "${DASHBOARD_SSH_IDENTITY_FILE}" DASHBOARD_SSH_IDENTITY_FILE_SHA1)
  if(NOT DASHBOARD_SSH_IDENTITY_FILE_SHA1 STREQUAL "8de7f79df9eb18344cf0e030d2ae3b658d81263b")
    file(WRITE "${DASHBOARD_WORKSPACE}/FAILURE")
    message(FATAL_ERROR
      "*** CTest Result: FAILURE BECAUSE SHA1 OF IDENTITY FILE WAS NOT CORRECT")
  endif()
  execute_process(COMMAND chmod 0400 "${DASHBOARD_SSH_IDENTITY_FILE}"
    RESULT_VARIABLE DASHBOARD_CHMOD_RESULT_VARIABLE)
  if(NOT DASHBOARD_CHMOD_RESULT_VARIABLE EQUAL 0)
    file(WRITE "${DASHBOARD_WORKSPACE}/FAILURE")
    message(FATAL_ERROR
      "*** CTest Result: FAILURE BECAUSE SETTING PERMISSIONS ON IDENTITY FILE WAS NOT SUCCESSFUL")
  endif()
  execute_process(COMMAND mktemp -q /tmp/git_ssh_XXXXXXXX
    RESULT_VARIABLE DASHBOARD_MKTEMP_RESULT_VARIABLE
    OUTPUT_VARIABLE DASHBOARD_MKTEMP_OUTPUT_VARIABLE)
  if(NOT DASHBOARD_MKTEMP_RESULT_VARIABLE EQUAL 0)
    file(WRITE "${DASHBOARD_WORKSPACE}/FAILURE")
    message(FATAL_ERROR
      "*** CTest Result: FAILURE BECAUSE CREATION OF TEMPORARY GIT_SSH FILE WAS NOT SUCCESSFUL")
  endif()
  set(DASHBOARD_GIT_SSH_FILE "${DASHBOARD_MKTEMP_OUTPUT_VARIABLE}")
  configure_file("${CMAKE_CURRENT_LIST_DIR}/tools/git_ssh.bash.in" "${DASHBOARD_GIT_SSH_FILE}" @ONLY)
  execute_process(COMMAND chmod 0755 "${DASHBOARD_GIT_SSH_FILE}"
    RESULT_VARIABLE DASHBOARD_CHMOD_RESULT_VARIABLE)
  if(NOT DASHBOARD_CHMOD_RESULT_VARIABLE EQUAL 0)
    file(WRITE "${DASHBOARD_WORKSPACE}/FAILURE")
    message(FATAL_ERROR
      "*** CTest Result: FAILURE BECAUSE SETTING PERMISSIONS ON GIT_SSH FILE WAS NOT SUCCESSFUL")
  endif()

  set(ENV{GIT_SSH} "${DASHBOARD_GIT_SSH_FILE}")
  file(WRITE "${DASHBOARD_WORKSPACE}/GIT_SSH" "${DASHBOARD_GIT_SSH_FILE}")
  message(STATUS "Using ENV{GIT_SSH} to set credentials")
endif()

# set model and track for submission
set(DASHBOARD_MODEL "Experimental")
if(TRACK STREQUAL "continuous")
  set(DASHBOARD_TRACK "Continuous")
elseif(TRACK STREQUAL "nightly")
  set(DASHBOARD_MODEL "Nightly")
  set(DASHBOARD_TRACK "Nightly")
else()
  set(DASHBOARD_TRACK "Experimental")
endif()

set(DASHBOARD_CONFIGURE_AND_BUILD_SUPERBUILD ON)
set(DASHBOARD_COVERAGE OFF)

set(DASHBOARD_FAILURE OFF)
set(DASHBOARD_FAILURES "")

set(DASHBOARD_CONFIGURATION_TYPE "Release")
set(DASHBOARD_TEST_TIMEOUT 500)

set(DASHBOARD_C_FLAGS "")
set(DASHBOARD_CXX_FLAGS "")
set(DASHBOARD_CXX_STANDARD "")
set(DASHBOARD_FORTRAN_FLAGS "")
set(DASHBOARD_SHARED_LINKER_FLAGS "")
set(DASHBOARD_VERBOSE_MAKEFILE ON)

# set compiler flags for coverage builds
if(COVERAGE)
  set(DASHBOARD_COVERAGE ON)
  set(DASHBOARD_CONFIGURATION_TYPE "Debug")
  set(DASHBOARD_COVERAGE_FLAGS "-fprofile-arcs -ftest-coverage")
  set(DASHBOARD_EXTRA_DEBUG_FLAGS "-O0")
  set(DASHBOARD_C_FLAGS
    "${DASHBOARD_COVERAGE_FLAGS} ${DASHBOARD_EXTRA_DEBUG_FLAGS} ${DASHBOARD_C_FLAGS}")
  set(DASHBOARD_CXX_FLAGS
    "${DASHBOARD_COVERAGE_FLAGS} ${DASHBOARD_EXTRA_DEBUG_FLAGS} ${DASHBOARD_CXX_FLAGS}")
  set(DASHBOARD_FORTRAN_FLAGS
    "${DASHBOARD_EXTRA_DEBUG_FLAGS} ${DASHBOARD_FORTRAN_FLAGS}")
  set(DASHBOARD_SHARED_LINKER_FLAGS
    "${DASHBOARD_COVERAGE_FLAGS} ${DASHBOARD_SHARED_LINKER_FLAGS}")

  if(COMPILER STREQUAL "clang")
    find_program(DASHBOARD_COVERAGE_COMMAND NAMES "llvm-cov")
    if(NOT DASHBOARD_COVERAGE_COMMAND)
      file(WRITE "${DASHBOARD_WORKSPACE}/FAILURE")
      message(FATAL_ERROR
        "*** CTest Result: FAILURE BECAUSE LLVM-COV WAS NOT FOUND")
    endif()
    set(DASHBOARD_COVERAGE_EXTRA_FLAGS "gcov")
  elseif(COMPILER STREQUAL "gcc")
    find_program(DASHBOARD_COVERAGE_COMMAND NAMES "gcov-4.9")
    if(NOT DASHBOARD_COVERAGE_COMMAND)
      file(WRITE "${DASHBOARD_WORKSPACE}/FAILURE")
      message(FATAL_ERROR
        "*** CTest Result: FAILURE BECAUSE GCOV-4.9 WAS NOT FOUND")
    endif()
  else()
    file(WRITE "${DASHBOARD_WORKSPACE}/FAILURE")
    message(FATAL_ERROR
      "*** CTest Result: FAILURE BECAUSE CTEST_COVERAGE_COMMAND WAS NOT SET")
  endif()

  set(CTEST_COVERAGE_COMMAND "${DASHBOARD_COVERAGE_COMMAND}")
  set(CTEST_COVERAGE_EXTRA_FLAGS "${DASHBOARD_COVERAGE_EXTRA_FLAGS}")

  set(CTEST_CUSTOM_COVERAGE_EXCLUDE
    ${CTEST_CUSTOM_COVERAGE_EXCLUDE}
    ".*/thirdParty/.*"
    ".*/test/.*"
  )
endif()

if(DEBUG)
  set(DASHBOARD_CONFIGURATION_TYPE "Debug")
endif()

if(DASHBOARD_CONFIGURATION_TYPE STREQUAL "Debug")
  set(DASHBOARD_TEST_TIMEOUT 1500)
endif()

if(MATLAB)
  math(EXPR DASHBOARD_TEST_TIMEOUT "${DASHBOARD_TEST_TIMEOUT} + 125")
endif()

set(ENV{CMAKE_CONFIG_TYPE} "${DASHBOARD_CONFIGURATION_TYPE}")
set(CTEST_CONFIGURATION_TYPE "${DASHBOARD_CONFIGURATION_TYPE}")
set(CTEST_TEST_TIMEOUT ${DASHBOARD_TEST_TIMEOUT})

set(DASHBOARD_CMAKE_FLAGS "-DCMAKE_BUILD_TYPE=${DASHBOARD_CONFIGURATION_TYPE}")

if(DASHBOARD_C_FLAGS)
  set(DASHBOARD_CMAKE_FLAGS
    "\"-DCMAKE_C_FLAGS:STRING=${DASHBOARD_C_FLAGS}\" ${DASHBOARD_CMAKE_FLAGS}")
endif()
if(DASHBOARD_CXX_FLAGS)
  set(DASHBOARD_CMAKE_FLAGS
    "\"-DCMAKE_CXX_FLAGS:STRING=${DASHBOARD_CXX_FLAGS}\" ${DASHBOARD_CMAKE_FLAGS}")
endif()
if(DASHBOARD_FORTRAN_FLAGS)
  set(DASHBOARD_CMAKE_FLAGS
    "\"-DCMAKE_Fortran_FLAGS:STRING=${DASHBOARD_FORTRAN_FLAGS}\" ${DASHBOARD_CMAKE_FLAGS}")
endif()
if(DASHBOARD_SHARED_LINKER_FLAGS)
  set(DASHBOARD_CMAKE_FLAGS
    "\"-DCMAKE_EXE_LINKER_FLAGS:STRING=${DASHBOARD_SHARED_LINKER_FLAGS}\" \"-DCMAKE_SHARED_LINKER_FLAGS:STRING=${DASHBOARD_SHARED_LINKER_FLAGS}\" ${DASHBOARD_CMAKE_FLAGS}")
endif()

set(DASHBOARD_CMAKE_FLAGS
  "-DCMAKE_VERBOSE_MAKEFILE:BOOL=${DASHBOARD_VERBOSE_MAKEFILE} ${DASHBOARD_CMAKE_FLAGS}")

if(DEFINED ENV{ghprbPullId})
  set(DASHBOARD_LONG_RUNNING_TESTS OFF)
else()
  set(DASHBOARD_LONG_RUNNING_TESTS ON)
endif()
set(DASHBOARD_CMAKE_FLAGS "-DLONG_RUNNING_TESTS:BOOL=${DASHBOARD_LONG_RUNNING_TESTS} ${DASHBOARD_CMAKE_FLAGS}")

set(DASHBOARD_WITH_BOT_CORE_LCMTYPES ON)
set(DASHBOARD_WITH_BULLET ON)
set(DASHBOARD_WITH_DIRECTOR ON)
set(DASHBOARD_WITH_EIGEN ON)
set(DASHBOARD_WITH_GOOGLE_STYLEGUIDE ON)
set(DASHBOARD_WITH_GOOGLETEST ON)
set(DASHBOARD_WITH_IPOPT ON)
set(DASHBOARD_WITH_LCM ON)
set(DASHBOARD_WITH_LIBBOT ON)
set(DASHBOARD_WITH_MESHCONVERTERS ON)
set(DASHBOARD_WITH_NLOPT ON)
set(DASHBOARD_WITH_OCTOMAP ON)
set(DASHBOARD_WITH_SIGNALSCOPE ON)
set(DASHBOARD_WITH_SPDLOG ON)
set(DASHBOARD_WITH_SWIG_MATLAB ON)
set(DASHBOARD_WITH_SWIGMAKE ON)
set(DASHBOARD_WITH_YAML_CPP ON)

if(OPEN_SOURCE)
  set(DASHBOARD_WITH_GUROBI OFF)
  set(DASHBOARD_WITH_MOSEK OFF)
  set(DASHBOARD_WITH_SNOPT OFF)
  set(DASHBOARD_WITH_SNOPT_PRECOMPILED ON)
else()
  set(DASHBOARD_GUROBI_DISTRO "$ENV{HOME}/gurobi6.0.5_linux64.tar.gz")
  if(EXISTS "${DASHBOARD_GUROBI_DISTRO}")
    set(DASHBOARD_WITH_GUROBI ON)
    set(ENV{GUROBI_DISTRO} "${DASHBOARD_GUROBI_DISTRO}")
  else()
    set(DASHBOARD_WITH_GUROBI OFF)
    message(WARNING "*** GUROBI_DISTRO was not found")
  endif()
  set(DASHBOARD_WITH_MOSEK ON)
  set(DASHBOARD_WITH_SNOPT ON)
  set(DASHBOARD_WITH_SNOPT_PRECOMPILED OFF)
endif()

if(MATLAB)
  set(DASHBOARD_WITH_AVL ON)
  set(DASHBOARD_WITH_SPOTLESS ON)
  set(DASHBOARD_WITH_TEXTBOOK ON)
  set(DASHBOARD_WITH_XFOIL ON)
  set(DASHBOARD_WITH_YALMIP ON)
  if(OPEN_SOURCE)
	set(DASHBOARD_WITH_IRIS OFF)
	set(DASHBOARD_WITH_SEDUMI OFF)
  else()
	set(DASHBOARD_WITH_IRIS ON)
	set(DASHBOARD_WITH_SEDUMI ON)
  endif()
else()
  set(DASHBOARD_WITH_AVL OFF)
  set(DASHBOARD_WITH_IRIS OFF)
  set(DASHBOARD_WITH_SEDUMI OFF)
  set(DASHBOARD_WITH_SPOTLESS OFF)
  set(DASHBOARD_WITH_TEXTBOOK OFF)
  set(DASHBOARD_WITH_XFOIL OFF)
  set(DASHBOARD_WITH_YALMIP OFF)
endif()

set(DASHBOARD_CMAKE_FLAGS
  "-DWITH_AVL:BOOL=${DASHBOARD_WITH_AVL} ${DASHBOARD_CMAKE_FLAGS}")
set(DASHBOARD_CMAKE_FLAGS
  "-DWITH_BOT_CORE_LCMTYPES:BOOL=${DASHBOARD_WITH_BOT_CORE_LCMTYPES} ${DASHBOARD_CMAKE_FLAGS}")
set(DASHBOARD_CMAKE_FLAGS
  "-DWITH_BULLET:BOOL=${DASHBOARD_WITH_BULLET} ${DASHBOARD_CMAKE_FLAGS}")
set(DASHBOARD_CMAKE_FLAGS
  "-DWITH_DIRECTOR:BOOL=${DASHBOARD_WITH_DIRECTOR} ${DASHBOARD_CMAKE_FLAGS}")
set(DASHBOARD_CMAKE_FLAGS
  "-DWITH_EIGEN:BOOL=${DASHBOARD_WITH_EIGEN} ${DASHBOARD_CMAKE_FLAGS}")
set(DASHBOARD_CMAKE_FLAGS
  "-DWITH_GOOGLE_STYLEGUIDE:BOOL=${DASHBOARD_WITH_GOOGLE_STYLEGUIDE} ${DASHBOARD_CMAKE_FLAGS}")
set(DASHBOARD_CMAKE_FLAGS
  "-DWITH_GOOGLETEST:BOOL=${DASHBOARD_WITH_GOOGLETEST} ${DASHBOARD_CMAKE_FLAGS}")
set(DASHBOARD_CMAKE_FLAGS
  "-DWITH_GUROBI:BOOL=${DASHBOARD_WITH_GUROBI} ${DASHBOARD_CMAKE_FLAGS}")
set(DASHBOARD_CMAKE_FLAGS
  "-DWITH_IPOPT:BOOL=${DASHBOARD_WITH_IPOPT} ${DASHBOARD_CMAKE_FLAGS}")
set(DASHBOARD_CMAKE_FLAGS
  "-DWITH_IRIS:BOOL=${DASHBOARD_WITH_IRIS} ${DASHBOARD_CMAKE_FLAGS}")
set(DASHBOARD_CMAKE_FLAGS
  "-DWITH_LCM:BOOL=${DASHBOARD_WITH_LCM} ${DASHBOARD_CMAKE_FLAGS}")
set(DASHBOARD_CMAKE_FLAGS
  "-DWITH_LIBBOT:BOOL=${DASHBOARD_WITH_LIBBOT} ${DASHBOARD_CMAKE_FLAGS}")
set(DASHBOARD_CMAKE_FLAGS
  "-DWITH_MESHCONVERTERS:BOOL=${DASHBOARD_WITH_MESHCONVERTERS} ${DASHBOARD_CMAKE_FLAGS}")
set(DASHBOARD_CMAKE_FLAGS
  "-DWITH_MOSEK:BOOL=${DASHBOARD_WITH_MOSEK} ${DASHBOARD_CMAKE_FLAGS}")
set(DASHBOARD_CMAKE_FLAGS
  "-DWITH_NLOPT:BOOL=${DASHBOARD_WITH_NLOPT} ${DASHBOARD_CMAKE_FLAGS}")
set(DASHBOARD_CMAKE_FLAGS
  "-DWITH_OCTOMAP:BOOL=${DASHBOARD_WITH_OCTOMAP} ${DASHBOARD_CMAKE_FLAGS}")
set(DASHBOARD_CMAKE_FLAGS
  "-DWITH_SEDUMI:BOOL=${DASHBOARD_WITH_SEDUMI} ${DASHBOARD_CMAKE_FLAGS}")
set(DASHBOARD_CMAKE_FLAGS
  "-DWITH_SIGNALSCOPE:BOOL=${DASHBOARD_WITH_SIGNALSCOPE} ${DASHBOARD_CMAKE_FLAGS}")
set(DASHBOARD_CMAKE_FLAGS
  "-DWITH_SNOPT:BOOL=${DASHBOARD_WITH_SNOPT} ${DASHBOARD_CMAKE_FLAGS}")
set(DASHBOARD_CMAKE_FLAGS
  "-DWITH_SNOPT_PRECOMPILED:BOOL=${DASHBOARD_WITH_SNOPT_PRECOMPILED} ${DASHBOARD_CMAKE_FLAGS}")
set(DASHBOARD_CMAKE_FLAGS
  "-DWITH_SPDLOG:BOOL=${DASHBOARD_WITH_SPDLOG} ${DASHBOARD_CMAKE_FLAGS}")
set(DASHBOARD_CMAKE_FLAGS
  "-DWITH_SPOTLESS:BOOL=${DASHBOARD_WITH_SPOTLESS} ${DASHBOARD_CMAKE_FLAGS}")
set(DASHBOARD_CMAKE_FLAGS
  "-DWITH_SWIG_MATLAB:BOOL=${DASHBOARD_WITH_SWIG_MATLAB} ${DASHBOARD_CMAKE_FLAGS}")
set(DASHBOARD_CMAKE_FLAGS
  "-DWITH_SWIGMAKE:BOOL=${DASHBOARD_WITH_SWIGMAKE} ${DASHBOARD_CMAKE_FLAGS}")
set(DASHBOARD_CMAKE_FLAGS
  "-DWITH_TEXTBOOK:BOOL=${DASHBOARD_WITH_TEXTBOOK} ${DASHBOARD_CMAKE_FLAGS}")
set(DASHBOARD_CMAKE_FLAGS
  "-DWITH_XFOIL:BOOL=${DASHBOARD_WITH_XFOIL} ${DASHBOARD_CMAKE_FLAGS}")
set(DASHBOARD_CMAKE_FLAGS
  "-DWITH_YALMIP:BOOL=${DASHBOARD_WITH_YALMIP} ${DASHBOARD_CMAKE_FLAGS}")
set(DASHBOARD_CMAKE_FLAGS
  "-DWITH_YAML_CPP:BOOL=${DASHBOARD_WITH_YAML_CPP} ${DASHBOARD_CMAKE_FLAGS}")

set(DASHBOARD_CDASH_SERVER "drake-cdash.csail.mit.edu")
set(DASHBOARD_NIGHTLY_START_TIME "00:00:00 EST")
set(CTEST_SITE "${DASHBOARD_SITE}")
set(CTEST_DROP_METHOD "https")
set(CTEST_DROP_SITE "${DASHBOARD_CDASH_SERVER}")
set(CTEST_DROP_SITE_CDASH ON)
set(CTEST_NIGHTLY_START_TIME "${DASHBOARD_NIGHTLY_START_TIME}")
set(DASHBOARD_SUPERBUILD_PROJECT_NAME "drake-superbuild")
set(DASHBOARD_DRAKE_PROJECT_NAME "Drake")
set(DASHBOARD_PROJECT_NAME "Drake-ROS")
set(CTEST_PROJECT_NAME "${DASHBOARD_SUPERBUILD_PROJECT_NAME}")
set(CTEST_DROP_LOCATION
    "/submit.php?project=${DASHBOARD_SUPERBUILD_PROJECT_NAME}")

set(CTEST_SOURCE_DIRECTORY "${DASHBOARD_WORKSPACE}/src/drake")
set(CTEST_BINARY_DIRECTORY "${DASHBOARD_WORKSPACE}/build")

# Set the following to suppress false positives
set(CTEST_CUSTOM_ERROR_EXCEPTION
   ${CTEST_CUSTOM_ERROR_EXCEPTION}
   "configure.ac:[0-9]*: installing"
   "swig/Makefile.am:30: installing './py-compile'"
)

if(DEFINED ENV{BUILD_ID})
  set(DASHBOARD_LABEL "jenkins-${CTEST_BUILD_NAME}-$ENV{BUILD_ID}")
  set_property(GLOBAL PROPERTY Label "${DASHBOARD_LABEL}")
else()
  message(WARNING "*** ENV{BUILD_ID} was not set")
  set(DASHBOARD_LABEL "")
endif()

# set pull request id
if(DEFINED ENV{ghprbPullId})
  set(CTEST_CHANGE_ID "$ENV{ghprbPullId}")
  set(DASHBOARD_CHANGE_TITLE "$ENV{ghprbPullTitle}")
  string(LENGTH "${DASHBOARD_CHANGE_TITLE}" DASHBOARD_CHANGE_TITLE_LENGTH)
  if(DASHBOARD_CHANGE_TITLE_LENGTH GREATER 30)
    string(SUBSTRING "${DASHBOARD_CHANGE_TITLE}" 0 27
      DASHBOARD_CHANGE_TITLE_SUBSTRING)
    set(DASHBOARD_CHANGE_TITLE "${DASHBOARD_CHANGE_TITLE_SUBSTRING}...")
  endif()
  set(DASHBOARD_BUILD_DESCRIPTION
    "*** Build Description: <a title=\"$ENV{ghprbPullTitle}\" href=\"$ENV{ghprbPullLink}\">PR ${CTEST_CHANGE_ID}</a>: ${DASHBOARD_CHANGE_TITLE}")
  message("${DASHBOARD_BUILD_DESCRIPTION}")
endif()

set(DASHBOARD_SUPERBUILD_START_MESSAGE
  "*** CTest Status: CONFIGURING / BUILDING SUPERBUILD")
message("
  ------------------------------------------------------------------------------
  ${DASHBOARD_SUPERBUILD_START_MESSAGE}
  ------------------------------------------------------------------------------
  ")

ctest_start("${DASHBOARD_MODEL}" TRACK "${DASHBOARD_TRACK}" QUIET)
ctest_update(SOURCE "${CTEST_SOURCE_DIRECTORY}" QUIET)
ctest_submit(PARTS Update QUIET)

set(DASHBOARD_BUILD_URL_FILE
  "${CTEST_BINARY_DIRECTORY}/${CTEST_BUILD_NAME}.url")
file(WRITE "${DASHBOARD_BUILD_URL_FILE}" "$ENV{BUILD_URL}")
ctest_upload(FILES "${DASHBOARD_BUILD_URL_FILE}" QUIET)
ctest_submit(PARTS Upload QUIET)

if(NOT DASHBOARD_FAILURE)
  set(CTEST_CONFIGURE_COMMAND "cmake -E create_symlink ${DASHBOARD_WORKSPACE}/src/drake/ros ${DASHBOARD_WORKSPACE}/src/drake_ros_integration")
  ctest_configure(BUILD "${DASHBOARD_WORKSPACE}"
                  SOURCE "${DASHBOARD_WORKSPACE}"
                  RETURN_VALUE DASHBOARD_CONFIGURE_RETURN_VALUE QUIET)
  if(NOT DASHBOARD_CONFIGURE_RETURN_VALUE EQUAL 0)
    message("*** CTest Result: FAILURE BECAUSE CREATION OF ROS SYMLINK WAS NOT SUCCESSFUL")
    set(DASHBOARD_FAILURE ON)
    list(APPEND DASHBOARD_FAILURES "CONFIGURE")
  endif()
endif()

if(NOT DASHBOARD_FAILURE)
  set(CTEST_CONFIGURE_COMMAND "catkin init")
  ctest_configure(BUILD "${DASHBOARD_WORKSPACE}"
                  SOURCE "${DASHBOARD_WORKSPACE}"
                  RETURN_VALUE DASHBOARD_CONFIGURE_RETURN_VALUE QUIET APPEND)
  if(NOT DASHBOARD_CONFIGURE_RETURN_VALUE EQUAL 0)
    message("*** CTest Result: FAILURE BECAUSE EXECUTION OF catkin init WAS NOT SUCCESSFUL")
    set(DASHBOARD_FAILURE ON)
    list(APPEND DASHBOARD_FAILURES "CONFIGURE")
  endif()
endif()

if(NOT DASHBOARD_FAILURE)
  set(CTEST_CONFIGURE_COMMAND "catkin config ${DASHBOARD_CMAKE_FLAGS} -DCATKIN_ENABLE_TESTING=True")
  ctest_configure(BUILD "${DASHBOARD_WORKSPACE}"
                  SOURCE "${DASHBOARD_WORKSPACE}"
                  RETURN_VALUE DASHBOARD_CONFIGURE_RETURN_VALUE QUIET APPEND)
  ctest_submit(PARTS Configure QUIET)
  if(NOT DASHBOARD_CONFIGURE_RETURN_VALUE EQUAL 0)
    message("*** CTest Result: FAILURE BECAUSE EXECUTION OF catkin config WAS NOT SUCCESSFUL")
    set(DASHBOARD_FAILURE ON)
    list(APPEND DASHBOARD_FAILURES "CONFIGURE")
  endif()
endif()

if(NOT DASHBOARD_FAILURE)
  set(CTEST_BUILD_COMMAND "catkin build --no-status -v -i drake")
  ctest_build(BUILD "${DASHBOARD_WORKSPACE}" APPEND
    RETURN_VALUE DASHBOARD_BUILD_RETURN_VALUE
    NUMBER_ERRORS DASHBOARD_NUMBER_BUILD_ERRORS QUIET)
  ctest_submit(PARTS Build QUIET)

  # ERROR detection doesn't work correctly with catkin... use error code instead
  if(NOT DASHBOARD_BUILD_RETURN_VALUE EQUAL 0)
    message("*** CTest Result: FAILURE BECAUSE OF BUILD FAILURES")
    set(DASHBOARD_FAILURE ON)
    list(APPEND DASHBOARD_FAILURES "BUILD")
  else()
    if(DASHBOARD_NUMBER_BUILD_WARNINGS EQUAL 1)
      set(DASHBOARD_WARNING ON)
      set(DASHBOARD_MESSAGE "SUCCESS BUT WITH 1 BUILD WARNING")
    elseif(DASHBOARD_NUMBER_BUILD_WARNINGS GREATER 1)
      set(DASHBOARD_WARNING ON)
      set(DASHBOARD_MESSAGE "SUCCESS BUT WITH ${DASHBOARD_NUMBER_BUILD_WARNINGS} BUILD WARNINGS")
    else()
      set(DASHBOARD_MESSAGE "SUCCESS")
    endif()
  endif()
endif()

# Set Dashboard to Drake to send Drake's Unit tests there
if(NOT DASHBOARD_FAILURE)
  # switch the dashboard to the drake only dashboard
  set(CTEST_PROJECT_NAME "${DASHBOARD_DRAKE_PROJECT_NAME}")
  set(CTEST_NIGHTLY_START_TIME "${DASHBOARD_NIGHTLY_START_TIME}")
  set(CTEST_DROP_METHOD "https")
  set(CTEST_DROP_SITE "${DASHBOARD_CDASH_SERVER}")
  set(CTEST_DROP_LOCATION "/submit.php?project=${DASHBOARD_DRAKE_PROJECT_NAME}")
  set(CTEST_DROP_SITE_CDASH ON)

  ctest_start("${DASHBOARD_MODEL}" TRACK "${DASHBOARD_TRACK}" QUIET)
  ctest_update(SOURCE "${CTEST_SOURCE_DIRECTORY}" QUIET)
  ctest_submit(PARTS Update QUIET)

  set(DASHBOARD_BUILD_URL_FILE
    "${CTEST_BINARY_DIRECTORY}/${CTEST_BUILD_NAME}.url")
  file(WRITE "${DASHBOARD_BUILD_URL_FILE}" "$ENV{BUILD_URL}")
  ctest_upload(FILES "${DASHBOARD_BUILD_URL_FILE}" QUIET)
  ctest_submit(PARTS Upload QUIET)

  ctest_test(BUILD "${DASHBOARD_WORKSPACE}/build/drake/drake" ${CTEST_TEST_ARGS}
    RETURN_VALUE DASHBOARD_TEST_RETURN_VALUE QUIET APPEND)
  ctest_submit(PARTS Test QUIET)
  if(NOT DASHBOARD_TEST_RETURN_VALUE EQUAL 0)
    set(DASHBOARD_UNSTABLE ON)
    list(APPEND DASHBOARD_UNSTABLES "TEST DRAKE")
  endif()
endif()

# Drake is built, blacklist to collect build info for drake_ros_integration only
# This way, catkin does not attempt to re-build drake
if(NOT DASHBOARD_FAILURE)
  set(CTEST_CONFIGURE_COMMAND "catkin config --blacklist drake")
  ctest_configure(BUILD "${DASHBOARD_WORKSPACE}"
                  SOURCE "${DASHBOARD_WORKSPACE}"
                  RETURN_VALUE DASHBOARD_CONFIGURE_RETURN_VALUE QUIET)
  ctest_submit(PARTS Configure QUIET)
  if(NOT DASHBOARD_CONFIGURE_RETURN_VALUE EQUAL 0)
    message("*** CTest Result: FAILURE BECAUSE EXECUTION OF catkin config WAS NOT SUCCESSFUL")
    set(DASHBOARD_FAILURE ON)
    list(APPEND DASHBOARD_FAILURES "CONFIGURE")
  endif()
endif()

# switch the dashboard to the drake only dashboard
set(CTEST_PROJECT_NAME "${DASHBOARD_PROJECT_NAME}")
set(CTEST_NIGHTLY_START_TIME "${DASHBOARD_NIGHTLY_START_TIME}")
set(CTEST_DROP_METHOD "https")
set(CTEST_DROP_SITE "${DASHBOARD_CDASH_SERVER}")
set(CTEST_DROP_LOCATION "/submit.php?project=${DASHBOARD_PROJECT_NAME}")
set(CTEST_DROP_SITE_CDASH ON)

if(NOT DASHBOARD_FAILURE)
  ctest_start("${DASHBOARD_MODEL}" TRACK "${DASHBOARD_TRACK}" QUIET)
  ctest_update(SOURCE "${CTEST_SOURCE_DIRECTORY}" QUIET)
  ctest_submit(PARTS Update QUIET)

  set(DASHBOARD_BUILD_URL_FILE
    "${CTEST_BINARY_DIRECTORY}/${CTEST_BUILD_NAME}.url")
  file(WRITE "${DASHBOARD_BUILD_URL_FILE}" "$ENV{BUILD_URL}")
  ctest_upload(FILES "${DASHBOARD_BUILD_URL_FILE}" QUIET)
  ctest_submit(PARTS Upload QUIET)

  set(CTEST_BUILD_COMMAND "catkin build --no-status -v -i")
  ctest_build(BUILD "${DASHBOARD_WORKSPACE}" APPEND
    RETURN_VALUE DASHBOARD_BUILD_RETURN_VALUE
    NUMBER_ERRORS DASHBOARD_NUMBER_BUILD_ERRORS QUIET)
  ctest_submit(PARTS Build QUIET)

  # ERROR detection doesn't work correctly with catkin... use error code instead
  if(NOT DASHBOARD_BUILD_RETURN_VALUE EQUAL 0)
    message("*** CTest Result: FAILURE BECAUSE OF BUILD FAILURES")
    set(DASHBOARD_FAILURE ON)
  else()
    if(DASHBOARD_NUMBER_BUILD_WARNINGS EQUAL 1)
      set(DASHBOARD_WARNING ON)
      set(DASHBOARD_MESSAGE "SUCCESS BUT WITH 1 BUILD WARNING")
    elseif(DASHBOARD_NUMBER_BUILD_WARNINGS GREATER 1)
      set(DASHBOARD_WARNING ON)
      set(DASHBOARD_MESSAGE "SUCCESS BUT WITH ${DASHBOARD_NUMBER_BUILD_WARNINGS} BUILD WARNINGS")
    else()
      set(DASHBOARD_MESSAGE "SUCCESS")
    endif()
  endif()
endif()

# Collect a list of all the ROS packages in the workspace
execute_process(COMMAND catkin list -u
                WORKING_DIRECTORY ${DASHBOARD_WORKSPACE}
                RESULT_VARIABLE RUN_RESULT
                OUTPUT_VARIABLE ROS_PACKAGES
                OUTPUT_STRIP_TRAILING_WHITESPACE)
# Replace newlines with ; to turn output into a list
string(REPLACE "\n" ";" ROS_PACKAGES_LIST "${ROS_PACKAGES}")

# Update ROS Environment after build, equivalent to sourcing devel/setup.bash
foreach(PKG ${ROS_PACKAGES_LIST})
  set(ENV{ROS_PACKAGE_PATH} "${DASHBOARD_WORKSPACE}/src/${PKG}:$ENV{ROS_PACKAGE_PATH}")
endforeach()
set(ENV{LD_LIBRARY_PATH} "${DASHBOARD_WORKSPACE}/devel/lib::$ENV{LD_LIBRARY_PATH}")
set(ENV{ROSLISP_PACKAGE_DIRECTORIES} "${DASHBOARD_WORKSPACE}/devel/share/common-lisp")
set(ENV{PKG_CONFIG_PATH} "${DASHBOARD_WORKSPACE}/devel/lib/pkgconfig:$ENV{PKG_CONFIG_PATH}")
set(ENV{CMAKE_PREFIX_PATH} "${DASHBOARD_WORKSPACE}/devel:$ENV{CMAKE_PREFIX_PATH}")

set(DASHBOARD_UNSTABLE OFF)
set(DASHBOARD_UNSTABLES "")

# Run tests for ROS Packages
if(NOT DASHBOARD_FAILURE)
  # Loop through all detected packages and run tests
  foreach(PKG ${ROS_PACKAGES_LIST})
    if (NOT ${PKG} STREQUAL "drake")
      ctest_test(BUILD "${DASHBOARD_WORKSPACE}/build/${PKG}" ${CTEST_TEST_ARGS}
        RETURN_VALUE DASHBOARD_TEST_RETURN_VALUE QUIET APPEND)
      if(NOT DASHBOARD_TEST_RETURN_VALUE EQUAL 0)
        set(DASHBOARD_UNSTABLE ON)
        list(APPEND DASHBOARD_UNSTABLES "TEST ${PKG}")
      endif()
      ctest_submit(PARTS Test QUIET)
    endif()
  endforeach()
  if(DASHBOARD_COVERAGE)
    ctest_coverage(RETURN_VALUE DASHBOARD_COVERAGE_RETURN_VALUE QUIET)
    if(NOT DASHBOARD_COVERAGE_RETURN_VALUE EQUAL 0)
      set(DASHBOARD_UNSTABLE ON)
      list(APPEND DASHBOARD_UNSTABLES "COVERAGE TOOL")
    endif()
    ctest_submit(PARTS Coverage QUIET)
  endif()
endif()

if(DASHBOARD_FAILURE)
  string(REPLACE ";" " / " DASHBOARD_FAILURES_STRING "${DASHBOARD_FAILURES}")
  set(DASHBOARD_MESSAGE "UNSTABLE DUE TO ${DASHBOARD_FAILURES_STRING} FAILURES")
  file(WRITE "${DASHBOARD_WORKSPACE}/FAILURE")
elseif(DASHBOARD_UNSTABLE)
  string(REPLACE ";" " / " DASHBOARD_UNSTABLES_STRING "${DASHBOARD_UNSTABLES}")
  set(DASHBOARD_MESSAGE
    "UNSTABLE DUE TO ${DASHBOARD_UNSTABLES_STRING} FAILURES")
  file(WRITE "${DASHBOARD_WORKSPACE}/UNSTABLE")
else()
  file(WRITE "${DASHBOARD_WORKSPACE}/SUCCESS")
endif()

set(DASHBOARD_MESSAGE "*** CTest Result: ${DASHBOARD_MESSAGE}")

if(DASHBOARD_CONFIGURE_AND_BUILD_SUPERBUILD AND DASHBOARD_LABEL)
  set(DASHBOARD_CDASH_SUPERBUILD_URL_MESSAGE
    "*** CDash Superbuild URL: https://${DASHBOARD_CDASH_SERVER}/index.php?project=${DASHBOARD_SUPERBUILD_PROJECT_NAME}&showfilters=1&filtercount=2&showfilters=1&filtercombine=and&field1=label&compare1=61&value1=${DASHBOARD_LABEL}&field2=buildstarttime&compare2=84&value2=now")
else()
  set(DASHBOARD_CDASH_SUPERBUILD_URL_MESSAGE "*** CDash Superbuild URL:")
endif()

if(NOT DASHBOARD_SUPERBUILD_FAILURE AND DASHBOARD_LABEL)
  set(DASHBOARD_CDASH_DRAKE_URL_MESSAGE
    "*** CDash Drake URL: https://${DASHBOARD_CDASH_SERVER}/index.php?project=${DASHBOARD_DRAKE_PROJECT_NAME}&showfilters=1&filtercount=2&showfilters=1&filtercombine=and&field1=label&compare1=61&value1=${DASHBOARD_LABEL}&field2=buildstarttime&compare2=84&value2=now")
else()
  set(DASHBOARD_CDASH_DRAKE_URL_MESSAGE "*** CDash Drake URL:")
endif()

if(NOT DASHBOARD_SUPERBUILD_FAILURE AND DASHBOARD_LABEL)
  set(DASHBOARD_CDASH_URL_MESSAGE
    "*** CDash URL: https://${DASHBOARD_CDASH_SERVER}/index.php?project=${DASHBOARD_PROJECT_NAME}&showfilters=1&filtercount=2&showfilters=1&filtercombine=and&field1=label&compare1=61&value1=${DASHBOARD_LABEL}&field2=buildstarttime&compare2=84&value2=now")
else()
  set(DASHBOARD_CDASH_URL_MESSAGE "*** CDash URL:")
endif()

message("
  ------------------------------------------------------------------------------
  ${DASHBOARD_MESSAGE}
  ------------------------------------------------------------------------------
  ${DASHBOARD_CDASH_SUPERBUILD_URL_MESSAGE}
  ------------------------------------------------------------------------------
  ${DASHBOARD_CDASH_DRAKE_URL_MESSAGE}
  ------------------------------------------------------------------------------
  ${DASHBOARD_CDASH_URL_MESSAGE}
  ------------------------------------------------------------------------------
  ")

if(NOT OPEN_SOURCE)
  if(EXISTS "${DASHBOARD_GIT_SSH_FILE}")
    file(REMOVE "${DASHBOARD_GIT_SSH_FILE}")
  endif()
  if(EXISTS "${DASHBOARD_SSH_IDENTITY_FILE}")
    execute_process(COMMAND chmod 0600 "${DASHBOARD_SSH_IDENTITY_FILE}"
      RESULT_VARIABLE DASHBOARD_CHMOD_RESULT_VARIABLE)
    if(DASHBOARD_CHMOD_RESULT_VARIABLE EQUAL 0)
      file(REMOVE "${DASHBOARD_SSH_IDENTITY_FILE}")
    else()
      message(WARNING "*** Setting permissions on identity file was not successful")
    endif()
  endif()
endif()

if(DASHBOARD_FAILURE)
  message(FATAL_ERROR
    "*** Return value set to NON-ZERO due to failure during build")
endif()
