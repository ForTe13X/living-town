#include "LivingTownCafeSlot.h"
#include "Misc/FileHelper.h"
#include "Misc/Paths.h"
#include "HAL/FileManager.h"
#if PLATFORM_WINDOWS
#include "Windows/WindowsHWrapper.h"
#endif

bool LivingTownCafeSlot::WriteAtomic(const FString& Path,const FString& Json,FString& Error)
{
    Error.Reset();
#if PLATFORM_WINDOWS
    const FString Final=FPaths::ConvertRelativePathToFull(Path);const FString Directory=FPaths::GetPath(Final);WCHAR Volume[MAX_PATH]={},FileSystem[MAX_PATH]={};
    if(!IFileManager::Get().MakeDirectory(*Directory,true)){Error=TEXT("slot_directory_unavailable");return false;}
    if(!GetVolumePathNameW(*Directory,Volume,MAX_PATH)||GetDriveTypeW(Volume)==DRIVE_REMOTE||!GetVolumeInformationW(Volume,nullptr,0,nullptr,nullptr,nullptr,FileSystem,MAX_PATH)||(FCString::Stricmp(FileSystem,TEXT("NTFS"))!=0&&FCString::Stricmp(FileSystem,TEXT("ReFS"))!=0)) {Error=TEXT("atomic_slot_requires_qualified_local_NTFS_or_ReFS");return false;}
    const FString Temp=Final+TEXT(".")+FGuid::NewGuid().ToString(EGuidFormats::Digits)+TEXT(".tmp");
    FString Readback;
    if(!FFileHelper::SaveStringToFile(Json,*Temp,FFileHelper::EEncodingOptions::ForceUTF8WithoutBOM)||!FFileHelper::LoadFileToString(Readback,*Temp)||Readback!=Json){IFileManager::Get().Delete(*Temp);Error=TEXT("slot_temp_write_or_readback_failed");return false;}
    // Same-directory rename only: never MOVEFILE_COPY_ALLOWED and never delete
    // Final before commit. A failed replacement leaves the previous slot intact.
    if(!MoveFileExW(*Temp,*Final,MOVEFILE_REPLACE_EXISTING|MOVEFILE_WRITE_THROUGH))
    {
        const uint32 Code=GetLastError();IFileManager::Get().Delete(*Temp);Error=FString::Printf(TEXT("atomic_slot_replace_failed_%u"),Code);return false;
    }
    return true;
#else
    Error=TEXT("atomic_slot_backend_not_qualified");return false;
#endif
}
