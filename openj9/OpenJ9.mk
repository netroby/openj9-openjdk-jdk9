# spec.gmk is generated by configure and contains many of the variable definitions use in this makefile
ifeq ($(wildcard $(SPEC)),)
  $(error OpenJ9.mk needs SPEC set to a proper spec.gmk)
endif
include $(SPEC)

# J9_PLATFORM should be defined in the spec.gmk via configure (Issue 58)
ifeq ($(OPENJDK_TARGET_BUNDLE_PLATFORM),linux-x64)
  export J9_PLATFORM=linux_x86-64
  export J9_PLATFORM_CODE=xa64
else ifeq ($(OPENJDK_TARGET_BUNDLE_PLATFORM),linux-ppc64le)
  export J9_PLATFORM=linux_ppc-64_le_gcc
  export J9_PLATFORM_CODE=xl64
else ifeq ($(OPENJDK_TARGET_BUNDLE_PLATFORM),linux-s390x)
  export J9_PLATFORM=linux_390-64
  export J9_PLATFORM_CODE=xz64
else
  $(error "Unsupported platform, contact support team: $(OPENJDK_TARGET_BUNDLE_PLATFORM)")
endif

# repo variables should be defined in the spec.gmk via configure
OPENJ9BINARIES_DIR := $(SRC_ROOT)/binaries
OPENJ9JIT_SRC_DIR  := $(SRC_ROOT)/tr.open
OPENJ9OMR_SRC_DIR  := $(SRC_ROOT)/omr
OPENJ9VM_SRC_DIR   := $(SRC_ROOT)/j9vm

OPENJ9JIT_SHA      := $(shell git -C $(OPENJ9JIT_SRC_DIR) rev-parse --short HEAD)
OPENJ9OMR_SHA      := $(shell git -C $(OPENJ9OMR_SRC_DIR) rev-parse --short HEAD)
OPENJ9VM_SHA       := $(shell git -C $(OPENJ9VM_SRC_DIR)  rev-parse --short HEAD)
ifeq (,$(OPENJ9JIT_SHA))
  $(error Could not determine tr.open SHA)
endif
ifeq (,$(OPENJ9OMR_SHA))
  $(error Could not determine omr SHA)
endif
ifeq (,$(OPENJ9VM_SHA))
  $(error Could not determine j9vm SHA)
endif

ENABLE_DDR=no
$(info ENABLE_DDR is set to $(ENABLE_DDR))

# we should try using the makeflags as defined by openjdk (Issue 59)
NUMCPU := $(shell grep -c ^processor /proc/cpuinfo)
#$(info NUMCPU = $(NUMCPU))
override MAKEFLAGS := -j $(NUMCPU)

.PHONY : clean-j9 clean-j9-dist compile-j9 stage-j9 run-preprocessors-j9 build-j9 compose compose-buildjvm generate-j9jcl-sources
.NOTPARALLEL :
build-j9 : stage-j9 run-preprocessors-j9 compile-j9

# openj9_copy_file
# ----------------
# param 1 = The target file to create or update.
# parma 2 = The source file to copy.
define openj9_copy_file
$1 : $2
	@$(MKDIR) -p $$(@D)
	@$(CP) $$< $$@
endef

# openj9_copy_tree
# ----------------
# param 1 = The target directory to create or update.
# parma 2 = The source directory to copy.
define openj9_copy_tree
  $(call openj9_copy_tree_impl,$(strip $(abspath $1)),$(strip $(abspath $2)))
endef

OPENJ9_MARKER_FILE := .up-to-date

define openj9_copy_tree_impl
  @$(MKDIR) -p $1
  @$(TAR) --create --directory=$2 $(if $(wildcard $1/$(OPENJ9_MARKER_FILE)),--newer=$1/$(OPENJ9_MARKER_FILE)) --exclude-vcs . | $(TAR) --extract --directory=$1 --touch
  @$(TOUCH) $1/$(OPENJ9_MARKER_FILE)
endef

# Rules to copy binary artifacts as necessary.

OPENJ9_BINARIES_JARS := \
  common/ibm/uma.jar \
  common/third/freemarker.jar \
  vm/ibm/j9ddr-autoblob.jar

OPENJ9_BINARIES_EXES := \
  extract_structures/linux_x86/extract_structures

OPENJ9_STAGED_BINARIES := \
  $(addprefix $(OUTPUT_ROOT)/vm/buildtools/,$(notdir $(OPENJ9_BINARIES_JARS)) $(OPENJ9_BINARIES_EXES))

OPENJ9_SOURCETOOLS_JARS := \
  dom4j-1.6.1.jar \
  xercesImpl.jar \
  xmlParserAPIs-2.0.2.jar

OPENJ9_STAGED_SOURCETOOLS := \
  $(addprefix $(OUTPUT_ROOT)/vm/sourcetools/lib/,$(OPENJ9_SOURCETOOLS_JARS))

$(foreach jar,$(OPENJ9_BINARIES_JARS),$(eval $(call openj9_copy_file,$(OUTPUT_ROOT)/vm/buildtools/$(notdir $(jar)),$(OPENJ9BINARIES_DIR)/$(jar))))

$(foreach jar,$(OPENJ9_SOURCETOOLS_JARS),$(eval $(call openj9_copy_file,$(OUTPUT_ROOT)/vm/sourcetools/lib/$(jar),$(OPENJ9BINARIES_DIR)/common/third/$(jar))))

$(eval $(call openj9_copy_file,$(OUTPUT_ROOT)/vm/buildtools/extract_structures/linux_x86/extract_structures,$(OPENJ9BINARIES_DIR)/vm/ibm/extract_structures))

# Comments for stage-j9
# Currently there is a staged location where j9 is built.  This is due to a number of reasons:
# 1. make currently leaves output file in current directory
# 2. generated source and header files
# 3. repo layout compared to source.zip layout
# See issue 49 for more information and actions to correct this action.

ifeq (yes,$(ENABLE_DDR))

# If DDR is enabled we can stage the files normally.

stage-j9-buildspecs :
	$(info Staging OpenJ9 buildspecs in $(OUTPUT_ROOT)/vm)
	$(call openj9_copy_tree,$(OUTPUT_ROOT)/vm/buildspecs,$(OPENJ9VM_SRC_DIR)/buildspecs)

OPENJ9_STAGED_BUILDSPECS := stage-j9-buildspecs

else

# If DDR is not enabled we use sed to filter .spec files.

# openj9_copy_spec
# ----------------
# param 1 = The target spec file to create or update.
# parma 2 = The source spec file to filter.
define openj9_copy_spec
$1 : $2
	@$(MKDIR) -p $$(@D)
	@$(SED) -e '/module_ddr/s/true/false/g' < $$< > $$@
endef

BUILDSPEC_ALL_FILES   := $(notdir $(wildcard $(OPENJ9VM_SRC_DIR)/buildspecs/*))
BUILDSPEC_SPEC_FILES  := $(filter     %.spec,$(BUILDSPEC_ALL_FILES))
BUILDSPEC_OTHER_FILES := $(filter-out %.spec,$(BUILDSPEC_ALL_FILES))

$(foreach file,$(BUILDSPEC_SPEC_FILES),$(eval $(call openj9_copy_spec,$(OUTPUT_ROOT)/vm/buildspecs/$(file),$(OPENJ9VM_SRC_DIR)/buildspecs/$(file))))

$(foreach file,$(BUILDSPEC_OTHER_FILES),$(eval $(call openj9_copy_file,$(OUTPUT_ROOT)/vm/buildspecs/$(file),$(OPENJ9VM_SRC_DIR)/buildspecs/$(file))))

OPENJ9_STAGED_BUILDSPECS := \
  $(addprefix $(OUTPUT_ROOT)/vm/buildspecs/,$(BUILDSPEC_ALL_FILES))

endif

stage-j9 : \
		$(OPENJ9_STAGED_BINARIES) \
		$(OPENJ9_STAGED_BUILDSPECS) \
		$(OPENJ9_STAGED_SOURCETOOLS)
	$(info Staging OpenJ9 debugtools in $(OUTPUT_ROOT)/vm)
	$(call openj9_copy_tree,$(OUTPUT_ROOT)/vm/debugtools,$(OPENJ9VM_SRC_DIR)/debugtools)

	$(info Staging OpenJ9 jcl in $(OUTPUT_ROOT)/vm)
	$(call openj9_copy_tree,$(OUTPUT_ROOT)/vm/jcl,$(OPENJ9VM_SRC_DIR)/jcl)

	$(info Staging OpenJ9 sourcetools in $(OUTPUT_ROOT)/vm)
	$(call openj9_copy_tree,$(OUTPUT_ROOT)/vm/sourcetools,$(OPENJ9VM_SRC_DIR)/sourcetools)

	$(info Staging OpenJ9 runtime in $(OUTPUT_ROOT)/vm)
	$(call openj9_copy_tree,$(OUTPUT_ROOT)/vm,$(OPENJ9VM_SRC_DIR)/runtime)

	$(info Staging OpenJ9 JIT in $(OUTPUT_ROOT)/vm)
	$(call openj9_copy_tree,$(OUTPUT_ROOT)/vm/tr.source,$(OPENJ9JIT_SRC_DIR))

	$(info Staging OpenJ9 OMR in $(OUTPUT_ROOT)/vm)
	$(call openj9_copy_tree,$(OUTPUT_ROOT)/vm/omr,$(OPENJ9OMR_SRC_DIR))

run-preprocessors-j9 : stage-j9
	$(info Running OpenJ9 preprocessors)
	$(info J9_PLATFORM set to $(J9_PLATFORM))
	# Capture JIT and OMR SHAs to be used in version strings;
	# possibly something that configure can do?
	# This needs to be done before uma runs.
	@echo '#define TR_LEVEL_NAME "$(OPENJ9JIT_SHA)"' \
		> $(OUTPUT_ROOT)/vm/tr.source/jit.version
	@echo '#define OMR_VERSION_STRING "$(OPENJ9OMR_SHA)"' \
		> $(OUTPUT_ROOT)/vm/omr/OMR_VERSION_STRING

	(export BOOT_JDK=$(BOOT_JDK) \
		&& cd $(OUTPUT_ROOT)/vm \
		&& $(MAKE) $(MAKEFLAGS) -f buildtools.mk \
			BUILD_ID=000000 \
			ENABLE_DDR=$(ENABLE_DDR) \
			J9VM_SHA=$(OPENJ9VM_SHA) \
			JAVA_HOME=$(BOOT_JDK) \
			OMR_DIR=$(OUTPUT_ROOT)/vm/omr \
			SPEC=$(J9_PLATFORM) \
			UMA_OPTIONS_EXTRA="-buildDate $(shell date +'%Y%m%d')" \
			tools \
	)

	# for xLinux there is a hardcoded reference in mkconstants.mk for gcc-4.6.  Openjdk minimum gcc is 4.8.2
	@$(SED) -i -e 's/gcc-4.6/gcc/g' $(OUTPUT_ROOT)/vm/makelib/mkconstants.mk
	# new compilers require different options for j9 to compile.  This needs review per platform.  Issue 60.
	@$(SED) -i -e 's/-O3 -fno-strict-aliasing/-O0 -fno-strict-aliasing -fno-stack-protector/g' $(OUTPUT_ROOT)/vm/makelib/targets.mk

compile-j9 : run-preprocessors-j9
	$(info Compiling OpenJ9 in $(OUTPUT_ROOT)/vm)
	(export OMR_DIR=$(OUTPUT_ROOT)/vm/omr && cd $(OUTPUT_ROOT)/vm && $(MAKE) $(MAKEFLAGS) all)
	$(info OpenJ9 compile complete)
	# libjvm.so and libjsig.so are required for compiling other java.base support natives
	@$(MKDIR) -p $(OUTPUT_ROOT)/support/modules_libs/java.base/server/
	@$(CP) -p $(OUTPUT_ROOT)/vm/j9vm_b156/libjvm.so $(OUTPUT_ROOT)/support/modules_libs/java.base/server/
	$(info Creating support/modules_libs/java.base/server/libjvm.so from J9 sources)
	@$(CP) -p $(OUTPUT_ROOT)/vm/libjsig.so $(OUTPUT_ROOT)/support/modules_libs/java.base/
	$(info Creating support/modules_libs/java.base/libjsig.so from J9 sources)

# comments for generate-j9jcl-sources
# currently generates all j9jcl source for every module each time its run.  PR 125757.
# currently only works for java.base
generate-j9jcl-sources :
	$(info Generating J9JCL sources)
	@$(MKDIR) -p $(SUPPORT_OUTPUTDIR)/j9jcl_sources
	@$(BOOT_JDK)/bin/java \
		-cp $(OPENJ9BINARIES_DIR)/vm/ibm/jpp.jar \
		-Dfile.encoding=US-ASCII \
		com.ibm.jpp.commandline.CommandlineBuilder \
			-verdict \
			-baseDir $(OPENJ9VM_SRC_DIR)/ \
			-config SIDECAR19-SE-B148  \
			-srcRoot jcl/ \
			-xml jpp_configuration.xml \
			-dest $(SUPPORT_OUTPUTDIR)/j9jcl_sources \
			-macro:define "com.ibm.oti.vm.library.version=29" \
			-tag:define "PLATFORM-$(J9_PLATFORM_CODE)" \
		> /dev/null
	@$(MKDIR) -p $(SUPPORT_OUTPUTDIR)/gensrc/java.base/
	@$(CP) -rp $(SUPPORT_OUTPUTDIR)/j9jcl_sources/java.base/* $(SUPPORT_OUTPUTDIR)/gensrc/java.base/
	@$(MKDIR) -p $(SUPPORT_OUTPUTDIR)/gensrc/jdk.attach/
	@$(CP) -rp $(SUPPORT_OUTPUTDIR)/j9jcl_sources/jdk.attach/* $(SUPPORT_OUTPUTDIR)/gensrc/jdk.attach/

# used to build the BUILD_JVM which is used to compile jmods and module.
compose-buildjvm :
	# identical to the compose target except it moves content to a different directory for the buildjvm
	# Issue 61.
	$(info J9 phase of Compose BUILD_JVM)
	@$(MKDIR) -p $(OUTPUT_ROOT)/jdk/lib/compressedrefs/
	@$(CP) -p $(OUTPUT_ROOT)/vm/*.so $(JDK_OUTPUTDIR)/lib/compressedrefs/
	@$(CP) -p $(OUTPUT_ROOT)/vm/J9TraceFormat.dat $(JDK_OUTPUTDIR)/lib/
	@$(CP) -p $(OUTPUT_ROOT)/vm/OMRTraceFormat.dat $(JDK_OUTPUTDIR)/lib/
	@$(CP) -p $(OUTPUT_ROOT)/vm/options.default $(JDK_OUTPUTDIR)/lib/
	@$(CP) -p $(OUTPUT_ROOT)/vm/java*properties $(JDK_OUTPUTDIR)/lib/
	@$(MKDIR) -p $(JDK_OUTPUTDIR)/lib/j9vm
	@$(CP) -p $(OUTPUT_ROOT)/vm/redirector/libjvm_b156.so $(JDK_OUTPUTDIR)/lib/j9vm/libjvm.so
	@$(CP) -p $(OUTPUT_ROOT)/vm/j9vm_b156/libjvm.so $(JDK_OUTPUTDIR)/lib/compressedrefs

# used to build the final images/jdk deliverable
compose :
	$(info J9 phase of Compose JDK)
	@$(MKDIR) -p $(IMAGES_OUTPUTDIR)/jdk/lib/compressedrefs/
	@$(CP) -p $(OUTPUT_ROOT)/vm/*.so $(IMAGES_OUTPUTDIR)/jdk/lib/compressedrefs/
	@$(CP) -p $(OUTPUT_ROOT)/vm/J9TraceFormat.dat $(IMAGES_OUTPUTDIR)/jdk/lib/
	@$(CP) -p $(OUTPUT_ROOT)/vm/OMRTraceFormat.dat $(IMAGES_OUTPUTDIR)/jdk/lib/
	@$(CP) -p $(OUTPUT_ROOT)/vm/options.default $(IMAGES_OUTPUTDIR)/jdk/lib/
	@$(CP) -p $(OUTPUT_ROOT)/vm/java*properties $(IMAGES_OUTPUTDIR)/jdk/lib/
	@$(MKDIR) -p $(IMAGES_OUTPUTDIR)/jdk/lib/j9vm
	@$(CP) -p $(OUTPUT_ROOT)/vm/redirector/libjvm_b156.so $(IMAGES_OUTPUTDIR)/jdk/lib/j9vm/libjvm.so
	@$(CP) -p $(OUTPUT_ROOT)/vm/j9vm_b156/libjvm.so $(IMAGES_OUTPUTDIR)/jdk/lib/compressedrefs

clean-j9 :
	( cd $(OUTPUT_ROOT)/vm && \
		$(MAKE) clean )
clean-j9-dist :
	$(RM) -fdr $(OUTPUT_ROOT)/vm
