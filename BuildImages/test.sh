# buildImages.sh
# script triggers packaging of modules, update of recipes and build of full target build (including kernel image and rootfs images)

#!/bin/bash

_DEBUG="on"

# include configs and global functions
. scripts/configs.sh
. scripts/globalFunctions.sh

# update sw version number (only build number)
updateSwBuildNo ()
{
    local buildNum=$(cat ${SEG_SW_VERSION_FILE} | sed -n 's/[0-9]\+.[0-9]\+.[0-9]\+.\([0-9]\+\)/\1/p')
    buildNum=$((${buildNum}+1))
    sed -i -e 's/\([0-9]\+.[0-9]\+.[0-9]\+.\)[0-9]\+/\1'$buildNum'/' ${SEG_SW_VERSION_FILE}
    #echo $buildNum
    return 0
}

updateSwPatchNo ()
{
    local patchNum=$(cat ${SEG_SW_VERSION_FILE} | sed -n 's/[0-9]\+.[0-9]\+.\([0-9]\+\).[0-9]\+/\1/p')
    patchNum=$((${patchNum}+1))
    sed -i -e 's/\([0-9]\+.[0-9]\+.\)[0-9]\+\(.[0-9]\+\)/\1'$patchNum'\2/' ${SEG_SW_VERSION_FILE}
    #echo $patchNum
    return 0
}

createBaselineLabel ()
{
    # baseline_type"_PRO_SEG_TARGET_"version"_"date"_"mksUser"_"remark
    local blType=REL
    local blProduct="PRO_SEG_TARGET"
    local blVersion=$(cat ${SEG_SW_VERSION_FILE})
    local blMksUser=`si servers | sed 's/\(.*\)@.*/\1/g' | head -n 1`
    local blDate=`date +%y%m%d`

    echo "${blType}_${blProduct}_${blVersion}_${blMksUser}_${blDate}"
}

getNextReleaseCandidateID ()
{
    if [[ $# -eq 1 ]]
    then 
        local try=0
        local found=0
        local id=""
        local relBasePath=$1

        while [ $found -eq 0 ]
        do
            try=$(echo $try+1 | bc)
            id="$relBasePath/rc$try"
            [ ! -e $id ] && found=1
        done

        echo ${id}
        return 0
    else
        return 1
    fi
}

compileUbootEnvSetupScript ()
{
    echo "Compiling script for UBoot environment setup"

    if [[ $# -eq 1 ]]
    then 
        local dest=$1
        
        pushd ../Tools/ubootEnvConfig > /dev/null
        mkimage -T script -C none -n 'SEG uBoot environment setup script' -d setEnvScript.txt setUbootEnv.img
        cp setUbootEnv.img ${dest}
        rm setUbootEnv.img

        popd > /dev/null

        return 0
    else
        return 1
    fi
}


isSandboxReadyForBaseline ()
{
    pushd ../ > /dev/null

    local lockedMembers=$(si viewlocks -R --filter=locked | wc -l)
    local modifiedWorkingFiles=$(si viewsandbox -R --filter=changed:working | grep "Working file" | wc -l)
    local outOfSyncFiles=$(si viewsandbox -R --filter=changed:sync | grep "Working file" | wc -l)

    if [[ ${lockedMembers} != 0 ]] || [[ ${modifiedWorkingFiles} != 0 ]] || [[ ${outOfSyncFiles} != 0 ]]
    then
        echo -e "\nSandbox is not in sync with repository! There are:" 

        if [[ ${lockedMembers} != 0 ]]
        then
            echo -e "\t${lockedMembers} locked members" 
        fi

        if [[ ${modifiedWorkingFiles} != 0 ]] 
        then
            echo -e "\t${modifiedWorkingFiles} modified working files"
        fi

        if [[ ${outOfSyncFiles} != "0" ]] 
        then
            echo -e "\t${outOfSyncFiles} out of sync members"
        fi
        echo -e "\nBaselining would not work correctly -> aborting release.\n" 

        #${JUST_ECHO_ON_DEBUG} exit
        popd > /dev/null
        return 1
    fi

    popd > /dev/null
    return 0
}




# script starts here

# check input params
if [ $# -eq 1 ]
then
    if [[ $1 == "local" ]] || [[ $1 == "install" ]] || [[ $1 == "release" ]]
    then
        buildType=$1
    else
        echo -e "\tError: buildImages.sh, unknown parameter!"
        echo -e "\tUsage: \"buildImages <local>, <install> or <release>\"."
    fi
else
    echo -e "\tError: buildImages.sh, wrong number of parameters!"
    echo -e "\tUsage: \"buildImages <local> or <release>\"."
    exit -1
fi    

# check for clean sandbox when releasing
if [[ $buildType == "release" ]]
then
    #isSandboxReadyForBaseline
    if [[ $? != 0 ]]
    then
        #echo ""
        ${JUST_ECHO_ON_DEBUG} exit
    fi
fi


# create tmp dir if necessary
if [ ! -d ${SEG_TMP_DIR} ]
then
    mkdir ${SEG_TMP_DIR}
fi

# aquire list of defined modules
ModuleList=$(GetModuleList)

${JUST_ECHO_ON_DEBUG} -e "\n... list of defined modules: \n${ModuleList}\n"

# create packages for all modules, change the recipes accordingly
if [[ -z ${ModuleList} ]]
then
    echo -e "\tError: seg_buildModule.sh, module list is empty!"
    exit
else    
    failed=0

    for i in ${ModuleList[@]}
    do
        moduleName=$(echo $i | cut -d: -f1)
        modulePath=$(echo $i | cut -d: -f2)

        DEBUG echo -e "\t... next list item: ${moduleName} - ${modulePath}"

        # package and update recipe (package name + revision)
        echo -e "... packaging module '$moduleName'"

        if [[ ${buildType} == "install" ]] || [[ ${buildType} == "release" ]]
        then
             ${JUST_ECHO_ON_DEBUG} si co --cpid=${MKS_RELEASE_TASK}:${MKS_RELEASE_CP} $(findRecipe $moduleName $modulePath)
             ${JUST_ECHO_ON_DEBUG} $(sleep 1)
        fi

         ${JUST_ECHO_ON_DEBUG} bash scripts/updatePackage.sh $moduleName $modulePath "yes"

        if [[ ! $? == 0 ]]
        then
            failed=1
            if [[ ${buildType} == "install" ]] || [[ ${buildType} == "release" ]]
            then
                ${JUST_ECHO_ON_DEBUG} si revert $(findRecipe $moduleName $modulePath)
            fi
        else
            if [[ ${buildType} == "install" ]] || [[ ${buildType} == "release" ]]
            then
                pushd ../ > /dev/null
                ${JUST_ECHO_ON_DEBUG} si ci --nocloseCP --cpid=${MKS_RELEASE_TASK}:${MKS_RELEASE_CP} --description "Package update" $(findRecipe $moduleName $modulePath)
                popd > /dev/null
            fi
        fi
    done


    if [[ ${failed} == 1 ]]
    then 
        echo -e "\tError: buildImages.sh, failed to package and update at least one module!"
    else
        # checkout sw-version file
        #${JUST_ECHO_ON_DEBUG} si co --cpid=${MKS_RELEASE_TASK}:${MKS_RELEASE_CP} ${SEG_SW_VERSION_FILE}
        #${JUST_ECHO_ON_DEBUG} $(sleep 1)

        if  [[ ${buildType} == "release" ]]
        then
            updateSwPatchNo
        fi

        # update sw version number (only build number)
        updateSwBuildNo

        # building whole target
        echo -e "... building full rootfs image"
        pushd ${SEG_YOCTO_CONFIG_PATH} > /dev/null

        #${JUST_ECHO_ON_DEBUG} bash startBuild.sh ${SEG_YOCTO_REPO_DIR} ${SEG_YOCTO_PLATFORM_NAME} core-image-minimal
		bash startBuild.sh ${SEG_YOCTO_REPO_DIR} ${SEG_YOCTO_PLATFORM_NAME} core-image-minimal

        #if [[ $? == 0 ]]
        #then
            # build ok -> checkin sw-version file
            #${JUST_ECHO_ON_DEBUG} si ci --nocloseCP --cpid=${MKS_RELEASE_TASK}:${MKS_RELEASE_CP} --description='Buildnumber update due to complete images build' ${SEG_SW_VERSION_FILE} 
        #else
            # build failed, if in release option -> don't check in patch number changes
            #if  [[ ${buildType} == "release" ]]
            #then
                #${JUST_ECHO_ON_DEBUG} si revert ${SEG_SW_VERSION_FILE} 
            #fi
        #fi

        popd > /dev/null

        # copy images to a temporary folder, folder name corresponds to build number
        buildDirName="build_$(cat ${SEG_SW_VERSION_FILE} | cut -d. -f 4)"

        mkdir -p ${SEG_TMP_DIR}/${buildDirName}
        cp ${SEG_YOCTO_CONFIG_PATH}/images/rootfs* ${SEG_TMP_DIR}/${buildDirName}
        cp ${SEG_YOCTO_CONFIG_PATH}/images/uImage ${SEG_TMP_DIR}/${buildDirName}
        cp ${SEG_SW_VERSION_FILE} ${SEG_TMP_DIR}/${buildDirName}/sw-version.txt
        chmod -R u+rwx ${SEG_TMP_DIR}/${buildDirName}

        if [[ ${buildType} == "local" ]]
        then 
            # nothing more to do for "local" option ---> leaving
            echo -e "... you can find the images at: '${SEG_TMP_DIR}/${buildDirName}'\n"
            exit 0
        else
            # continue for options "install" and "release"

            # copy images also to temporary tftpfboot directory
            releaseBasePath="${SEG_INSTALL_DIR}releaseV$(cat ${SEG_SW_VERSION_FILE} | cut -d. -f 1-2)"
            installDirName="${releaseBasePath}/tmp"

            mkdir -p ${installDirName}
            cp -r ${SEG_TMP_DIR}/${buildDirName}/* ${installDirName}
            chmod -R ug+rwx ${installDirName} 


            compileUbootEnvSetupScript ${installDirName}


            if [[ ${buildType} == "install" ]]
            then 
                # nothing more to do for install option
                echo -e "... you can find the images at: '${installDirName}'\n"
                exit 0
            else
                # continue for option "release"
                releaseCandidatePath=${releaseBasePath}/$(cat ${SEG_SW_VERSION_FILE})
                
                # create special copy and save as release candidate
                mkdir -p ${releaseCandidatePath}
                cp -r ${SEG_TMP_DIR}/${buildDirName}/* ${releaseCandidatePath}

                # create update file in release candidate folder
                pushd ../Target/Update > /dev/null
                ${JUST_ECHO_ON_DEBUG} bash createUpdFile.sh ${SEG_TMP_DIR}/${buildDirName} update_tmp  
                ${JUST_ECHO_ON_DEBUG} cp segV_update.tbz2 ${releaseCandidatePath}
                rm -rf update_tmp
                rm segV_update.tbz2
                popd > /dev/null

                chmod -R ugo=rx ${releaseCandidatePath} 

                # checkout, copy and checkin release binaries
                ${JUST_ECHO_ON_DEBUG} si co -R --cpid=${MKS_RELEASE_TASK}:${MKS_RELEASE_CP} ${SEG_RELEASE_DIR}/project.pj
                echo "copying files to release candidates folder ... "
                cp ${releaseCandidatePath}/* ${SEG_RELEASE_DIR}
                ${JUST_ECHO_ON_DEBUG} si ci -R --checkinUnchanged --nocloseCP --cpid=${MKS_RELEASE_TASK}:${MKS_RELEASE_CP} --description='new release candidate' ${SEG_RELEASE_DIR}/project.pj


                # revert sanity file
                ${JUST_ECHO_ON_DEBUG} si revert -f ../Target/SystemSW/Toolchain/yocto/conf/sanity_info

                # check sandbox again before baselining
                isSandboxReadyForBaseline
                if [[ $? != 0 ]]
                then
                    ${JUST_ECHO_ON_DEBUG} exit
                fi

                # setting baseline
                baselineName=$(createBaselineLabel)
                blRemark=""
                ok="n"

                while [[ ${ok} == "n" ]]
                do
                    if [[ ${blRemark} == "" ]]
                    then                        
                        echo -e "\nBaselining source with this label: '${baselineName}'"
                    else 
                        echo -e "\nBaselining source with this label: '${baselineName}_${blRemark}'"
                    fi
                    echo -e "Do you want to use this label (Enter 'n' if you want to add a custom remark)? (y/n):"
                    
                    read ok

                    if [[ $ok == "n" ]]
                    then
                        echo -e "Please type in the remark now, hit 'enter' to omit remark:"
                        read blRemark
                    fi
                done

                if [[ ${blRemark} != "" ]]
                then
                    baselineName="${baselineName}_${blRemark}"
                fi

                echo -e "\nBaselining source with label: '${baselineName}'"

                pushd ../ > /dev/null
                ${JUST_ECHO_ON_DEBUG} si checkpoint --quiet -L ${baselineName} -d 'seg release candidate'
                ${JUST_ECHO_ON_DEBUG} si addlabel --quiet -R -L ${baselineName}
                popd
            fi
        fi
    fi
fi

echo -e "\nDone\n"


