# AzureBakery

Simple module for producing production-ready VM images.  Standard Windows Server images require Windows Update to be run and often do not contain desired Windows Features fully installed--this can prolong scale outs and complcate initialization scripts.  The `New-BakedImage` cmdlet will create a VHD in blob storage containing all the specified Windows Features fully installed (and rebooted if necessary), as well as installed with the latest Windows Updates.  

`New-BakedImage` complements the existing Azure Resource Manager API.  The returned VHD blob URL can be passed into a correctly configured ARM template to create a managed disk from the generalized VHD.  `New-BakedImage` explicitly uses VHD blobs, as VHD blobs can be copied across regions (managed disks cannot), and can be turned into managed disks at their destination region within an ARM template or using PowerShell.

Install from PowerShell Gallery with `Install-Module AzureBakery`.  Run `help New-BakedImage` for usage information.
