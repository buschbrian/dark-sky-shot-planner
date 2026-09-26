# Sky view catalogs: sources and licences

Written by `ios/scripts/build-sky-catalogs.py`; details and checks in
`docs/data-licensing.md` ("Sky view catalogs").

- `bsc5-stars.csv`: every star to V 6.5 from the Bright Star Catalogue, 5th
  Revised Ed. (Preliminary), Hoffleit & Warren 1991, as NASA HEASARC's
  `heasarc_bsc5p` table. data.gov lists it as a U.S. Government Work
  (public domain). Credit: "Bright Star Catalogue, Hoffleit & Warren
  (Yale University Observatory / NASA ADC), via NASA HEASARC".
- `constellations.csv`: constellation stick figures and label positions from
  d3-celestial (Olaf Frohn), commit 7e720a3de062059d4c5400a379146a601d9010e0,
  whose figures follow the IAU and Sky & Telescope charts (Roger Sinnott,
  Rick Fienberg), released under CC BY 4.0. Vertices are replaced by the
  BSC5 HR number of the matching star.
- `star-names.csv`: IAU Working Group on Star Names approved names, keyed
  by BSC5 HR number.

d3-celestial licence (BSD 3-Clause):

Copyright (c) 2015, Olaf Frohn
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice,
   this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.
3. Neither the name of the copyright holder nor the names of its
   contributors may be used to endorse or promote products derived from this
   software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.
