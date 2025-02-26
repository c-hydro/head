=========
Changelog
=========

Version 1.2.0 [2025-02-26]
**************************
PACKAGE: operational release

PRODUCTS:
	- H26: fix errors in opening file (file is available, but data are corrupted);
	- H122: fix errors in opening file (file is available, but data are corrupted).

TOOLS:
	- DOWNLOADER:
		- H16, H103, H122: [METOP] add executable to download the soil moisture data from ftp service.
		- H26: [ECMWF] add executable to run the algorithm of soil moisture products.

Version 1.1.0 [2024-11-18]
**************************
PACKAGE: operational release

PRODUCTS:
	- H61: fix bug for managing file with defined/not defined variable(s);
	- H122: add feature to mask data using a binary file.

Version 1.0.0 [2024-06-01]
**************************
PACKAGE: beta release (first development and codes refactoring)

PRODUCTS:
	- H10, H12, H13, H34: add algorithms and configuration files of snow products;
	- H60, H61, H64: add algorithms and configuration files of precipitation products;
	- H26, H122: add algorithms and configuration files of soil moisture products.
	
BINARIES:
	- H10, H12, H13, H34: add executable to run the algorithm of snow products;
	- H60, H61, H64: add executable to run the algorithm of precipitation products;
	- H26, H122: add executable to run the algorithm of soil moisture products.

TOOLS:
	- DOWNLOADER:
		- H10, H12, H13, H34: add executable to download the snow data from ftp service;
		- H60, H61, H64: add executable to download the precipitation data from ftp service;
		- H26, H122: add executable to download the soil moisture data from ftp service. 
	- CLEANER:
		- procedure to remove empty folders;
		- method to remove deprecated files (ref days);
		- method to remove deprecated filed (ref minutes).
	- SHRINKER:
		- method to shrinker soil moisture data;
		- method to shrinker snow data.

