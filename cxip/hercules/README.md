# cxip Hercules module

Notes, so I don't forget:

```
git clone https://github.com/SDL-Hercules-390/hyperion.git
cd hyperion
ln -s /path/to/channel/cxip/hercules/cxip.c
git apply /path/to/channel/cxip/hercules/hyperion.patch
./configure
make
```

This should build `cxip.so` in `.libs`, it can be loaded with:

```
LDMOD /path/to/hyperion/.libs/cxip
```
