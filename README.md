luci-0.11
=========
luci-bismark based on luci 0.11

List of changes (explanation of past commits)

1. add bismark-experiments and bismark-passive
https://github.com/shahifaqeer/luci-0.11/commit/8bb2ff4aa16840722b9871a3d92a490f68c6a044

applications/luci-bismark-experiments-manager/luasrc/controller/bismark/experiments.lua
applications/luci-bismark-experiments-manager/luasrc/model/cbi/bismark-experiments-manager/general.lua
applications/luci-bismark-experiments-manager/Makefile
applications/luci-bismark-passive/Makefile
applications/luci-bismark-passive/luasrc/controller/bismark/passive.lua
applications/luci-bismark-passive/luasrc/model/cbi/bismark-passive/general.lua

- same as projectbismark/luci-bismark


2. changes to luci makefile
https://github.com/shahifaqeer/luci-0.11/blob/8bb2ff4aa16840722b9871a3d92a490f68c6a044/contrib/package/luci/Makefile
- changed package version to 2
- added eval(call) blocks for luci-bismark-experiments-manager and luci-bismark-passive


3. Added fathom_rpc module (my intern stuff) but removed this from current version into another repo: https://github.com/shahifaqeer/luci-0.11
