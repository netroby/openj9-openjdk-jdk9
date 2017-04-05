#spec.gmk is generated by configure and contains many of the variable definitions use in this makefile
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

J9_BUILD_ID ?= 326747

# JDK_BUILD should be defined in the spec.gmk via configure.  This is required as long as j9 requires a classlib.properties file (PR 125728)
JDK_BUILD = $(lastword $(subst 9+, ,$(shell hg id | awk '{print $$2}')))

# repo variables should be defined in the spec.gmk via configure
OPENJ9VM_SRC_DIR   := $(SRC_ROOT)/j9vm
OPENJ9JIT_SRC_DIR  := $(SRC_ROOT)/tr.open
OPENJ9OMR_SRC_DIR  := $(SRC_ROOT)/omr
OPENJ9BINARIES_DIR := $(SRC_ROOT)/binaries

ENABLE_DDR=no
$(info ENABLE_DDR is set to $(ENABLE_DDR))

define \n



endef

# we should try using the makeflags as defined by openjdk (Issue 59)
NUMCPU := $(shell grep -c ^processor /proc/cpuinfo)
#$(info NUMCPU = $(NUMCPU))
override MAKEFLAGS := -j $(NUMCPU)

.PHONY : clean-j9 clean-j9-dist compile-j9 stage-j9 run-preprocessors-j9 build-j9 compose compose-buildjvm generate-j9jcl-sources
.NOTPARALLEL :
build-j9 : stage-j9 run-preprocessors-j9 compile-j9

# Comments for stage-j9
# currently there is a staged location that j9 is built out of.  This is because of a number of reasons:
# 1. make currently leaves output file in current directory
# 2. generated source and header files
# 3. repo layout compared to source.zip layout
# See Issue 49 for more information and actions to correct this action.

stage-j9 :
	$(info Staging OpenJ9 components in $(OUTPUT_ROOT)/vm)
	@$(MKDIR) -p $(OUTPUT_ROOT)/vm
	@$(CP) -pr $(OPENJ9VM_SRC_DIR)/* $(OUTPUT_ROOT)/vm
	@$(CP) -pr $(OUTPUT_ROOT)/vm/runtime/* $(OUTPUT_ROOT)/vm
	@$(RM) -rf $(OUTPUT_ROOT)/vm/runtime
	@$(CP) -pr $(OPENJ9VM_SRC_DIR)/buildspecs $(OUTPUT_ROOT)/vm
	@$(MKDIR) -p $(OUTPUT_ROOT)/vm/buildtools/extract_structures/linux_x86/
	@$(CP) -p $(OPENJ9BINARIES_DIR)/vm/ibm/extract_structures $(OUTPUT_ROOT)/vm/buildtools/extract_structures/linux_x86/
	@$(CP) -p $(OPENJ9BINARIES_DIR)/common/ibm/uma.jar $(OUTPUT_ROOT)/vm/buildtools/
	@$(CP) -p $(OPENJ9BINARIES_DIR)/common/third/freemarker.jar $(OUTPUT_ROOT)/vm/buildtools/
	@$(CP) -p $(OPENJ9BINARIES_DIR)/vm/ibm/j9ddr-autoblob.jar $(OUTPUT_ROOT)/vm/buildtools/
	@$(CP) -p $(OPENJ9BINARIES_DIR)/common/third/xercesImpl.jar $(OUTPUT_ROOT)/vm/sourcetools/lib/
	@$(CP) -p $(OPENJ9BINARIES_DIR)/common/third/dom4j-1.6.1.jar $(OUTPUT_ROOT)/vm/sourcetools/lib/
	@$(CP) -p $(OPENJ9BINARIES_DIR)/common/third/xmlParserAPIs-2.0.2.jar $(OUTPUT_ROOT)/vm/sourcetools/lib/
	@$(CP) -pr $(OPENJ9JIT_SRC_DIR)/* $(OUTPUT_ROOT)/vm/tr.source/
	@$(MKDIR) -p $(OUTPUT_ROOT)/vm/omr
	@$(CP) -pr $(OPENJ9OMR_SRC_DIR)/* $(OUTPUT_ROOT)/vm/omr/

	# Until all modules linked to java.base and java.management can compile cleanly, we need to omit. Issue 27
	@$(SED) -i -e 's/, com.ibm.sharedclasses//g' '$(OUTPUT_ROOT)/vm/jcl/src/java.base/module-info.java'
	@$(SED) -i -e '/sharedclasses/d' '$(OUTPUT_ROOT)/vm/jcl/src/java.base/module-info.java'
	@$(SED) -i -e '/com.ibm.cuda/d' '$(OUTPUT_ROOT)/vm/jcl/src/java.base/module-info.java'
	@$(SED) -i -e '/openj9.gpu/d' '$(OUTPUT_ROOT)/vm/jcl/src/java.base/module-info.java'
	@$(SED) -i -e '/dtfj/d' '$(OUTPUT_ROOT)/vm/jcl/src/java.base/module-info.java'
	@$(SED) -i -e '/sharedclasses/d' '$(OUTPUT_ROOT)/vm/jcl/src/java.management/module-info.java'

	# disable ddr spec flags
	$(if $(findstring no,$(ENABLE_DDR)), @$(SED) -i -e '/module_ddr/s/true/false/g' '$(OUTPUT_ROOT)/vm/buildspecs/$(J9_PLATFORM).spec')

	# use gcc in omr configuration file on ppc le platform
	$(if $(findstring linux_ppc,$(J9_PLATFORM)), @$(SED) -i -e 's/CXXLINKSHARED=$$$$(CC)/CXXLINKSHARED=$$$$(CXX)/g' '$(OUTPUT_ROOT)/vm/omr/glue/configure_includes/configure_linux_ppc.mk')

run-preprocessors-j9 : stage-j9
	$(info Running OpenJ9 preprocessors)
	$(info J9_PLATFORM set to $(J9_PLATFORM))
	# generate omr and jit version strings based on sha; possibly something that configure can do? These need to be performed before uma runs.
	@echo "#define TR_LEVEL_NAME \"`git -C $(OPENJ9JIT_SRC_DIR) describe --tags`\"" > $(OUTPUT_ROOT)/vm/tr.source/jit.version
	@echo "#define OMR_VERSION_STRING \"`git -C $(OPENJ9OMR_SRC_DIR) rev-parse --short HEAD`\"" > $(OUTPUT_ROOT)/vm/omr/OMR_VERSION_STRING

	(export BOOT_JDK=$(BOOT_JDK) && cd $(OUTPUT_ROOT)/vm && $(MAKE) $(MAKEFLAGS) -f buildtools.mk SPEC=$(J9_PLATFORM) ENABLE_DDR=$(ENABLE_DDR) JAVA_HOME=$(BOOT_JDK) BUILD_ID=000000 UMA_OPTIONS_EXTRA="-buildDate $(shell date +'%Y%m%d')" tools)

	# generating the sha can happen earlier but j9version.h is an uma generated file
	$(eval J9VM_SHA=$(shell git -C $(OPENJ9VM_SRC_DIR) rev-parse --short HEAD))
	@$(SED) -i -e 's/developer.compile/$(J9VM_SHA)/g' $(OUTPUT_ROOT)/vm/include/j9version.h

	# for xLinux there is a hardcoded reference in mkconstants.mk for gcc-4.6.  Openjdk minimum gcc is 4.8.2
	@$(SED) -i -e 's/gcc-4.6/gcc/g' $(OUTPUT_ROOT)/vm/makelib/mkconstants.mk
	# new compilers require different options for j9 to compile.  This needs review per platform.  Issue 60.
	@$(SED) -i -e 's/O3 -fno-strict-aliasing/O0 -Wno-format -Wno-unused-result -fno-strict-aliasing -fno-stack-protector/g' $(OUTPUT_ROOT)/vm/makelib/targets.mk

compile-j9 : run-preprocessors-j9
	$(info Compiling OpenJ9 in $(OUTPUT_ROOT)/vm)
	(cd $(OUTPUT_ROOT)/vm && $(MAKE) $(MAKEFLAGS) all)
	$(info OpenJ9 compile complete)
	# libjvm.so and libjsig.so are required for compiling other java.base support natives
	@$(MKDIR) -p $(OUTPUT_ROOT)/support/modules_libs/java.base/server/
	@$(CP) -pr $(OUTPUT_ROOT)/vm/j9vm_b156/libjvm.so $(OUTPUT_ROOT)/support/modules_libs/java.base/server/
	$(info Creating support/modules_libs/java.base/server/libjvm.so from J9 sources)
	@$(CP) -p $(OUTPUT_ROOT)/vm/libjsig.so $(OUTPUT_ROOT)/support/modules_libs/java.base/
	$(info Creating support/modules_libs/java.base/libjsig.so from J9 sources)

# comments for generate-j9jcl-sources
# currently generates all j9jcl source for every module each time its run.  PR 125757.
# currently only works for java.base
generate-j9jcl-sources :
	$(info Generating J9JCL sources)
	@$(BOOT_JDK)/bin/java \
		-cp "$(OPENJ9BINARIES_DIR)/vm/ibm/*:$(OPENJ9BINARIES_DIR)/common/third/*" \
		com.ibm.jpp.commandline.CommandlineBuilder \
			-verdict \
			-baseDir $(OPENJ9VM_SRC_DIR)/ \
			-config SIDECAR19-SE \
			-srcRoot jcl/ \
			-xml jpp_configuration.xml \
			-dest $(SUPPORT_OUTPUTDIR)/j9jcl_sources \
			-macro:define "com.ibm.oti.vm.library.version=29;com.ibm.oti.jcl.build=$(J9_BUILD_ID)" \
			-tag:define "PLATFORM-$(J9_PLATFORM_CODE)" \
			-tag:remove null \
		> /dev/null
	@$(FIND) $(SUPPORT_OUTPUTDIR)/j9jcl_sources -name module-info.java -exec mv "{}" "{}.extra" ";"
	@$(MKDIR) -p $(SUPPORT_OUTPUTDIR)/gensrc/java.base/
	@$(CP) -rp $(SUPPORT_OUTPUTDIR)/j9jcl_sources/java.base/* $(SUPPORT_OUTPUTDIR)/gensrc/java.base/

# used to build the BUILD_JVM which is used to compile jmods and module.
compose-buildjvm :
	# identical to the compose target except it moves content to a different directory for the buildjvm
	# Issue 61.
	$(info J9 phase of Compose BUILD_JVM)
	@$(CP) -p $(OPENJ9VM_SRC_DIR)/../tooling/jvmbuild_scripts/jvm.cfg $(OUTPUT_ROOT)/jdk/lib/
	@$(SED) -i -e 's/shape=vm.shape/shape=b$(JDK_BUILD)/g' $(OUTPUT_ROOT)/vm/classlib.properties
	@$(MKDIR) -p $(OUTPUT_ROOT)/jdk/lib/compressedrefs/
	@$(CP) -p $(OUTPUT_ROOT)/vm/*.so $(JDK_OUTPUTDIR)/lib/compressedrefs/
	@$(CP) -p $(OUTPUT_ROOT)/vm/J9TraceFormat.dat $(JDK_OUTPUTDIR)/lib/
	@$(CP) -p $(OUTPUT_ROOT)/vm/OMRTraceFormat.dat $(JDK_OUTPUTDIR)/lib/
	@$(CP) -p $(OUTPUT_ROOT)/vm/options.default $(JDK_OUTPUTDIR)/lib/
	@$(CP) -p $(OUTPUT_ROOT)/vm/java*properties $(JDK_OUTPUTDIR)/lib/
	@$(MKDIR) -p $(JDK_OUTPUTDIR)/lib/j9vm
	@$(CP) -p $(OUTPUT_ROOT)/vm/redirector/libjvm_b156.so $(JDK_OUTPUTDIR)/lib/j9vm/libjvm.so
	@$(CP) -p $(OUTPUT_ROOT)/vm/j9vm_b156/libjvm.so $(JDK_OUTPUTDIR)/lib/compressedrefs
	@$(CP) -p $(OUTPUT_ROOT)/vm/classlib.properties $(JDK_OUTPUTDIR)/lib

# used to build the final images/jdk deliverable
compose :
	$(info J9 phase of Compose JDK)
	@$(CP) -p $(OPENJ9VM_SRC_DIR)/../tooling/jvmbuild_scripts/jvm.cfg $(IMAGES_OUTPUTDIR)/jdk/lib/
	@$(SED) -i -e 's/shape=vm.shape/shape=b$(JDK_BUILD)/g' $(OUTPUT_ROOT)/vm/classlib.properties
	@$(MKDIR) -p $(IMAGES_OUTPUTDIR)/jdk/lib/compressedrefs/
	@$(CP) -p $(OUTPUT_ROOT)/vm/*.so $(IMAGES_OUTPUTDIR)/jdk/lib/compressedrefs/
	@$(CP) -p $(OUTPUT_ROOT)/vm/J9TraceFormat.dat $(IMAGES_OUTPUTDIR)/jdk/lib/
	@$(CP) -p $(OUTPUT_ROOT)/vm/OMRTraceFormat.dat $(IMAGES_OUTPUTDIR)/jdk/lib/
	@$(CP) -p $(OUTPUT_ROOT)/vm/options.default $(IMAGES_OUTPUTDIR)/jdk/lib/
	@$(CP) -p $(OUTPUT_ROOT)/vm/java*properties $(IMAGES_OUTPUTDIR)/jdk/lib/
	@$(MKDIR) -p $(IMAGES_OUTPUTDIR)/jdk/lib/j9vm
	@$(CP) -p $(OUTPUT_ROOT)/vm/redirector/libjvm_b156.so $(IMAGES_OUTPUTDIR)/jdk/lib/j9vm/libjvm.so
	@$(CP) -p $(OUTPUT_ROOT)/vm/j9vm_b156/libjvm.so $(IMAGES_OUTPUTDIR)/jdk/lib/compressedrefs
	@$(CP) -p $(OUTPUT_ROOT)/vm/classlib.properties $(IMAGES_OUTPUTDIR)/jdk/lib

clean-j9 :
	( cd $(OUTPUT_ROOT)/vm && \
		$(MAKE) clean )
clean-j9-dist :
	$(RM) -fdr $(OUTPUT_ROOT)/vm
