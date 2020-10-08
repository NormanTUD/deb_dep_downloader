# deb_dep_downloader
Downloads all dependencies from the debian-repository

# Examples

> perl deb_deb_downloader.pl --debug --download_suggested --download_recommended --arch=ppc64el --outdir=dl --version=sid --package=latexmk

> perl deb_deb_downloader.pl --download_suggested --download_recommended --arch=amd64 --version=wheezy --package=kde-full --mirror_country=us
