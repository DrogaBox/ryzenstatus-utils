# Notices

The `GPU/` folder of RyzenStatus is released under the MIT license (see `LICENSE`); the rest
of RyzenStatus is GPL-3.0-or-later. This file lists what in this folder was written by
others, and what the build or the tests download without it being part of the repository.
Keep it, with `LICENSE`, next to every kext, plug-in or package built from this folder.

## In the repository

### Input checks from vcn-video-decoders

The decoders were first published in the *vcn-video-decoders* repository
(https://github.com/wh0ami7/vcn-video-decoders). Bounds and null checks in
`decode/av1/av1parse.c`, `decode/av1/vcnav1.c`, `decode/av1/AV1VCNDecoder.c`,
`decode/vp9/vp9parse.c`, `decode/vp9/vcnvp9.c` and `decode/vp9/VP9VCNDecoder.c`, and in the
test programs under `decode/tests/`, were written there by Izzy and are used under that
repository's license:

> MIT License
>
> Copyright (c) 2026 DrogaBox (https://github.com/DrogaBox) and Izzy
> (https://github.com/wh0ami7)
>
> Permission is hereby granted, free of charge, to any person obtaining a copy of this
> software and associated documentation files (the "Software"), to deal in the Software
> without restriction, including without limitation the rights to use, copy, modify, merge,
> publish, distribute, sublicense, and/or sell copies of the Software, and to permit
> persons to whom the Software is furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in all copies or
> substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
> INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
> PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE
> FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
> OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
> DEALINGS IN THE SOFTWARE.

### VP9 default probability tables

`decode/vp9/ac_vcn_vp9_default.h` comes from Mesa (`src/amd/common`), copyright Advanced
Micro Devices, Inc., MIT license. The file keeps its original license header.

### Short byte patterns

`encode/tool/patches.c` and `encode/tests/wide_test.c` hold short byte sequences used to
recognise the point in Apple's encoder where a setting is corrected, and to check that the
bytes found are the expected ones before changing anything. They are locators, not a copy
of Apple's code. No Apple binary, header or decompiled code is in this repository.

## Downloaded by the build or the tests, not in the repository

| What | Used for | License | Fetched by |
|---|---|---|---|
| Lilu (DEBUG build): plugin headers and `plugin_start.cpp`, which is compiled into the kexts | Building `VCNEncodeFloor.kext`, `VCNVTLoader.kext` and `GPUSensors.kext` | BSD 3-Clause, © vit9696 and the Acidanthera team | `tools/bootstrap.sh` |
| MacKernelSDK: kernel headers and `libkmod.a`, which is linked into the kexts | Building `VCNEncodeFloor.kext`, `VCNVTLoader.kext` and `GPUSensors.kext` | Apple Public Source License 2.0 (the SDK's `LICENSE.txt`); each header keeps Apple's notice | `tools/bootstrap.sh` |
| OpenCore `Docs/Sample.plist` | Tests of the tool that edits an OpenCore config | BSD 3-Clause, © the Acidanthera team | `tools/bootstrap.sh` |
| AV1 conformance streams | Parser tests | Alliance for Open Media test vectors | `tests/fetch_media.sh` |
| VP9 conformance streams, valid and deliberately invalid | Parser tests | libvpx test vectors, © the WebM project authors | `tests/fetch_media.sh` |

The built kexts (`VCNEncodeFloor.kext`, `VCNVTLoader.kext`, `GPUSensors.kext`) contain
code compiled from Lilu's `plugin_start.cpp`. If you distribute them, keep Lilu's license
with them. This is that license, from Lilu 1.7.2 (`LICENSE.txt`):

> Copyright (c) 2016-2018, vit9696
> All rights reserved.
>
> Redistribution and use in source and binary forms, with or without modification, are
> permitted provided that the following conditions are met:
>
> 1. Redistributions of source code must retain the above copyright notice, this list of
>    conditions and the following disclaimer.
>
> 2. Redistributions in binary form must reproduce the above copyright notice, this list of
>    conditions and the following disclaimer in the documentation and/or other materials
>    provided with the distribution.
>
> 3. Neither the name of the copyright holder nor the names of its contributors may be used
>    to endorse or promote products derived from this software without specific prior
>    written permission.
>
> THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS
> OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
> MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
> COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
> EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
> SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
> HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR
> TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
> SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

The kexts also link `libkmod.a` from MacKernelSDK: Apple's kmod start and stop code
(`c_start.o`, `c_stop.o`), under the Apple Public Source License 2.0.

## Trademarks

AMD and Radeon are trademarks of Advanced Micro Devices, Inc. Apple, macOS, Safari and
VideoToolbox are trademarks of Apple Inc. This project is not affiliated with, sponsored
or endorsed by either company.
