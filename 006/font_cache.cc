 /*
 * Copyright (C) 2006, 2008 Apple Inc. All rights reserved.
 * Copyright (C) 2007 Nicholas Shanks <webkit@nickshanks.com>
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 * 1.  Redistributions of source code must retain the above copyright
 *     notice, this list of conditions and the following disclaimer.
 * 2.  Redistributions in binary form must reproduce the above copyright
 *     notice, this list of conditions and the following disclaimer in the
 *     documentation and/or other materials provided with the distribution.
 * 3.  Neither the name of Apple Computer, Inc. ("Apple") nor the names of
 *     its contributors may be used to endorse or promote products derived
 *     from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY APPLE AND ITS CONTRIBUTORS "AS IS" AND ANY
 * EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL APPLE OR ITS CONTRIBUTORS BE LIABLE FOR ANY
 * DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
 * THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#include "third_party/blink/renderer/platform/fonts/font_cache.h"

#include <limits>
#include <memory>

#include "base/command_line.h"
#include "base/strings/string_number_conversions.h"
#include "components/ungoogled/ungoogled_switches.h"

#include "base/debug/alias.h"
#include "base/feature_list.h"
#include "base/notreached.h"
#include "base/strings/escape.h"
#include "base/system/sys_info.h"
#include "base/timer/elapsed_timer.h"
#include "base/trace_event/process_memory_dump.h"
#include "base/trace_event/trace_event.h"
#include "build/build_config.h"
#include "skia/ext/font_utils.h"
#include "third_party/blink/public/common/features.h"
#include "third_party/blink/public/platform/platform.h"
#include "third_party/blink/renderer/platform/font_family_names.h"
#include "third_party/blink/renderer/platform/fonts/alternate_font_family.h"
#include "third_party/blink/renderer/platform/fonts/font_cache_client.h"
#include "third_party/blink/renderer/platform/fonts/font_data_cache.h"
#include "third_party/blink/renderer/platform/fonts/font_description.h"
#include "third_party/blink/renderer/platform/fonts/font_fallback_map.h"
#include "third_party/blink/renderer/platform/fonts/font_fallback_priority.h"
#include "third_party/blink/renderer/platform/fonts/font_global_context.h"
#include "third_party/blink/renderer/platform/fonts/font_performance.h"
#include "third_party/blink/renderer/platform/fonts/font_platform_data_cache.h"
#include "third_party/blink/renderer/platform/fonts/font_unique_name_lookup.h"
#include "third_party/blink/renderer/platform/fonts/simple_font_data.h"
#include "third_party/blink/renderer/platform/heap/thread_state.h"
#include "third_party/blink/renderer/platform/instrumentation/tracing/web_memory_allocator_dump.h"
#include "third_party/blink/renderer/platform/instrumentation/tracing/web_process_memory_dump.h"
#include "third_party/blink/renderer/platform/json/json_parser.h"
#include "third_party/blink/renderer/platform/json/json_values.h"
#include "third_party/blink/renderer/platform/wtf/text/atomic_string_hash.h"
#include "third_party/blink/renderer/platform/wtf/text/code_point_iterator.h"
#include "third_party/blink/renderer/platform/wtf/text/string_hash.h"
#include "third_party/blink/renderer/platform/wtf/vector.h"
#include "ui/gfx/font_list.h"

#if BUILDFLAG(IS_WIN)
#include "third_party/skia/include/ports/SkTypeface_win.h"
#endif

namespace blink {

const char kColorEmojiLocale[] = "und-Zsye";
const char kMonoEmojiLocale[] = "und-Zsym";

#if BUILDFLAG(IS_ANDROID)
extern const char kNotoColorEmojiCompat[] = "Noto Color Emoji Compat";
#endif

#if BUILDFLAG(IS_LINUX) || BUILDFLAG(IS_CHROMEOS)
float FontCache::device_scale_factor_ = 1.0;
#endif

#if BUILDFLAG(IS_WIN)
bool FontCache::antialiased_text_enabled_ = false;
bool FontCache::lcd_text_enabled_ = false;
#endif  // BUILDFLAG(IS_WIN)

FontCache& FontCache::Get() {
  return FontGlobalContext::GetFontCache();
}

FontCache::FontCache() = default;

FontCache::~FontCache() = default;

void FontCache::Trace(Visitor* visitor) const {
  visitor->Trace(font_cache_clients_);
  visitor->Trace(font_platform_data_cache_);
  visitor->Trace(font_data_cache_);
  visitor->Trace(font_fallback_map_);
#if BUILDFLAG(IS_MAC)
  visitor->Trace(character_fallback_cache_);
#endif
}

#if !BUILDFLAG(IS_MAC)
const FontPlatformData* FontCache::SystemFontPlatformData(
    const FontDescription& font_description) {
  const AtomicString& family = FontCache::SystemFontFamily();
#if BUILDFLAG(IS_LINUX) || BUILDFLAG(IS_CHROMEOS) || BUILDFLAG(IS_FUCHSIA) || \
    BUILDFLAG(IS_IOS)
  if (family.empty() || family == font_family_names::kSystemUi)
    return nullptr;
#else
  DCHECK(!family.empty() && family != font_family_names::kSystemUi);
#endif
  return GetFontPlatformData(font_description, FontFaceCreationParams(family),
                             AlternateFontName::kNoAlternate);
}
#endif

// 获取平台特定的字体列表
static std::vector<std::string> GetPlatformFonts(const std::string& platform) {
  if (platform == "windows") {
    return {
      "Arial", "Arial Black",
      "Bahnschrift",
      "Calibri", "Cambria", "Cambria Math", "Candara", "Cascadia Code", "Cascadia Mono", "Comic Sans MS", "Consolas", "Constantia", "Corbel", "Courier New",
      "Ebrima",
      "Franklin Gothic Medium",
      "Gabriola", "Gadugi", "Georgia",
      "HoloLens MDL2 Assets",
      "Impact", "Ink Free",
      "Javanese Text",
      "Leelawadee UI", "Lucida Console", "Lucida Sans Unicode",
      "Malgun Gothic", "Marlett", "Microsoft Himalaya", "Microsoft JhengHei", "Microsoft New Tai Lue", "Microsoft PhagsPa", "Microsoft Sans Serif", "Microsoft Tai Le", "Microsoft YaHei", "Microsoft Yi Baiti", "MingLiU-ExtB", "Mongolian Baiti", "MS Gothic", "MV Boli", "Myanmar Text",
      "Nirmala UI",
      "Palatino Linotype",
      "Segoe Fluent Icons", "Segoe MDL2 Assets", "Segoe Print", "Segoe Script", "Segoe UI", "Segoe UI Emoji", "Segoe UI Historic", "Segoe UI Symbol", "Segoe UI Variable", "SimSun", "Sitka", "Sylfaen", "Symbol",
      "Tahoma", "Times New Roman", "Trebuchet MS",
      "Verdana",
      "Webdings", "Wingdings",
      "Yu Gothic"
    };
  } else if (platform == "macos") {
    return {
      "Academy Engraved LET", "Adelle Sans Devanagari", "AkayaKanadaka", "AkayaTelivigala", "Al Bayan", "Al Firat", "Al Khalil", "Al Nile", "Al Rafidain", "Al Rafidain Al Fanni", "Al Tarikh", "Algiers", "American Typewriter", "Andale Mono", "Annai MN", "Apple Braille", "Apple Chancery", "Apple Color Emoji", "Apple LiGothic", "Apple LiSung", "Apple SD Gothic Neo", "Apple Symbols", "AppleGothic", "AppleMyungjo", "Arial", "Arial Hebrew", "Arial Narrow", "Arial Rounded MT", "Arial Unicode MS", "Arima Koshi", "Arima Madurai", "Asphalt", "Athelas", "Avenir", "Avenir Next", "Ayuthaya",
      "Baghdad", "Bai Jamjuree", "Balega", "Baloo 2", "Baloo Bhai 2", "Baloo Bhaijaan", "Baloo Bhaina 2", "Baloo Chettan 2", "Baloo Da 2", "Baloo Paaji 2", "Baloo Tamma 2", "Baloo Tammudu 2", "Baloo Thambi 2", "Bangla MN", "Bangla Sangam MN", "Bank Gothic", "Baoli SC", "Baoli TC", "Baskerville", "Basra", "Bebas Neue", "Beirut", "BiauKaiHK", "BiauKaiTC", "Big Caslon", "BIZ UDGothic", "BIZ UDMincho", "Blackmoor LET", "BlairMdITC TT", "BM DoHyeon OTF", "BM HANNA 11yrs old OTF", "BM HANNA Air OTF", "BM HANNA Pro OTF", "BM JUA OTF", "BM KIRANGHAERANG OTF", "BM YEONSUNG OTF", "Bodoni 72", "Bodoni 72 Oldstyle", "Bodoni 72 Smallcaps", "Bodoni Ornaments", "Book Antiqua", "Bookman Old Style", "Bordeaux Roman Bold LET", "Bradley Hand", "Braganza", "Brill Italic", "Brill Roman", "Brush Script MT",
      "Cambay Devanagari", "Canela", "Canela Deck", "Canela Text", "Capitals", "Carlito", "Catamaran", "Century Gothic", "Century Schoolbook", "Chakra Petch", "Chalkboard", "Chalkboard SE", "Chalkduster", "Charcoal CY", "Charm", "Charmonman", "Charter", "Cochin", "Comic Sans MS", "Copperplate", "Corsiva Hebrew", "Courier", "Courier New",
      "Damascus", "Dash", "Dear Joe Four", "DecoType Naskh", "Devanagari MT", "Devanagari Sangam MN", "DFKaiShu-SB-Estd-BF", "Didot", "Dijla", "DIN Alternate", "DIN Condensed", "Diwan Kufi", "Diwan Thuluth", "Domaine Display", "Druk", "Druk Text", "Druk Wide",
      "Euphemia UCAS",
      "Fahkwang", "Fakt Slab Stencil Pro", "Farah", "Farisi", "Forgotten Futurist", "Founders Grotesk", "Founders Grotesk Text", "Futura",
      "Galvji", "Garamond", "GB18030 Bitmap", "Geeza Pro", "Geneva", "Geneva CY", "Georgia", "Gill Sans", "Gotu", "Grantha Sangam MN", "Graphik", "Graphik Compact", "Gujarati MT", "Gujarati Sangam MN", "GungSeo", "Gurmukhi MN", "Gurmukhi MT", "Gurmukhi Sangam MN",
      "Hannotate SC", "Hannotate TC", "HanziPen SC", "HanziPen TC", "HeadLineA", "Hei", "Heiti SC", "Heiti TC", "Helvetica", "Helvetica CY", "Helvetica Neue", "Herculanum", "Hiragino Kaku Gothic Pro", "Hiragino Kaku Gothic ProN", "Hiragino Kaku Gothic Std", "Hiragino Kaku Gothic StdN", "Hiragino Maru Gothic Pro", "Hiragino Maru Gothic ProN", "Hiragino Mincho Pro", "Hiragino Mincho ProN", "Hiragino Sans", "Hiragino Sans CNS", "Hiragino Sans GB", "Hiragino Sans TC", "Hoefler Text", "Hopper Script", "Hubballi",
      "Impact", "InaiMathi", "Iowan Old Style", "ITF Devanagari", "ITF Devanagari Marathi",
      "Jaini", "Jaini Purva", "Jazz LET", "Journal Sans New",
      "K2D", "Kai", "Kailasa", "Kaiti SC", "Kaiti TC", "Kannada MN", "Kannada Sangam MN", "Katari", "Kavivanar", "Kefa", "Khmer MN", "Khmer Sangam MN", "Kigelia", "Kigelia Arabic", "Klee", "Kodchasan", "Kohinoor Bangla", "Kohinoor Devanagari", "Kohinoor Gujarati", "Kohinoor Telugu", "KoHo", "Kokonor", "Koufi Abjadi", "Krub", "Krungthep", "KufiStandardGK",
      "Lahore Gurmukhi", "Laimoon", "Lantinghei SC", "Lantinghei TC", "Lao MN", "Lao Sangam MN", "Lava Devanagari", "Lava Kannada", "Lava Telugu", "Libian SC", "Libian TC", "LiHei Pro", "LingWai SC", "LingWai TC", "LiSong Pro", "Lucida Grande", "Luminari",
      "Maku", "Malayalam MN", "Malayalam Sangam MN", "Mali", "Marion", "Marker Felt", "Menlo", "Microsoft Sans Serif", "Mishafi", "Mishafi Gold", "Modak", "Mona Lisa Solid ITC TT", "Monaco", "Mshtakan", "Mukta", "Mukta Malar", "Mukta Vaani", "MuktaMahee", "Muna", "Myanmar MN", "Myanmar Sangam MN", "Myriad Arabic",
      "Nadeem", "Nanum Brush Script", "Nanum Pen Script", "NanumGothic", "NanumMyeongjo", "New Peninim MT", "Niramit", "Nisan", "Nom Na Tong", "Noteworthy", "Noto Nastaliq Urdu", "Noto Sans Adlam", "Noto Sans Armenian", "Noto Sans Avestan", "Noto Sans Bamum", "Noto Sans Bassa Vah", "Noto Sans Batak", "Noto Sans Bhaiksuki", "Noto Sans Brahmi", "Noto Sans Buginese", "Noto Sans Buhid", "Noto Sans Canadian Aboriginal", "Noto Sans Carian", "Noto Sans Caucasian Albanian", "Noto Sans Chakma", "Noto Sans Cham", "Noto Sans Coptic", "Noto Sans Cuneiform", "Noto Sans Cypriot", "Noto Sans Duployan", "Noto Sans Egyptian Hieroglyphs", "Noto Sans Elbasan", "Noto Sans Glagolitic", "Noto Sans Gothic", "Noto Sans Gunjala Gondi", "Noto Sans Hanifi Rohingya", "Noto Sans Hanunoo", "Noto Sans Hatran", "Noto Sans Imperial Aramaic", "Noto Sans Inscriptional Pahlavi", "Noto Sans Inscriptional Parthian", "Noto Sans Javanese", "Noto Sans Kaithi", "Noto Sans Kannada", "Noto Sans Kayah Li", "Noto Sans Kharoshthi", "Noto Sans Khojki", "Noto Sans Khudawadi", "Noto Sans Lepcha", "Noto Sans Limbu", "Noto Sans Linear A", "Noto Sans Linear B", "Noto Sans Lisu", "Noto Sans Lycian", "Noto Sans Lydian", "Noto Sans Mahajani", "Noto Sans Mandaic", "Noto Sans Manichaean", "Noto Sans Marchen", "Noto Sans Masaram Gondi", "Noto Sans Meetei Mayek", "Noto Sans Mende Kikakui", "Noto Sans Meroitic", "Noto Sans Miao", "Noto Sans Modi", "Noto Sans Mongolian", "Noto Sans Mro", "Noto Sans Multani", "Noto Sans Myanmar", "Noto Sans Nabataean", "Noto Sans New Tai Lue", "Noto Sans Newa", "Noto Sans NKo", "Noto Sans Ol Chiki", "Noto Sans Old Hungarian", "Noto Sans Old Italic", "Noto Sans Old North Arabian", "Noto Sans Old Permic", "Noto Sans Old Persian", "Noto Sans Old South Arabian", "Noto Sans Old Turkic", "Noto Sans Oriya", "Noto Sans Osage", "Noto Sans Osmanya", "Noto Sans Pahawh Hmong", "Noto Sans Palmyrene", "Noto Sans Pau Cin Hau", "Noto Sans PhagsPa", "Noto Sans Phoenician", "Noto Sans Psalter Pahlavi", "Noto Sans Rejang", "Noto Sans Samaritan", "Noto Sans Saurashtra", "Noto Sans Sharada", "Noto Sans Siddham", "Noto Sans Sora Sompeng", "Noto Sans Sundanese", "Noto Sans Syloti Nagri", "Noto Sans Syriac", "Noto Sans Tagalog", "Noto Sans Tagbanwa", "Noto Sans Tai Le", "Noto Sans Tai Tham", "Noto Sans Tai Viet", "Noto Sans Takri", "Noto Sans Thaana", "Noto Sans Tifinagh", "Noto Sans Tirhuta", "Noto Sans Ugaritic", "Noto Sans Vai", "Noto Sans Wancho", "Noto Sans Warang Citi", "Noto Sans Yi", "Noto Sans Zawgyi", "Noto Serif Ahom", "Noto Serif Balinese", "Noto Serif Hmong Nyiakeng", "Noto Serif Kannada", "Noto Serif Myanmar", "Noto Serif Yezidi", "November Bangla Traditional",
      "October Compressed Devanagari", "October Compressed Gujarati", "October Compressed Gurmukhi", "October Compressed Kannada", "October Compressed Meetei Mayek", "October Compressed Odia", "October Compressed Ol Chiki", "October Compressed Tamil", "October Compressed Telugu", "October Condensed Devanagari", "October Condensed Gujarati", "October Condensed Gurmukhi", "October Condensed Kannada", "October Condensed Meetei Mayek", "October Condensed Odia", "October Condensed Ol Chiki", "October Condensed Tamil", "October Condensed Telugu", "October Devanagari", "October Gujarati", "October Gurmukhi", "October Kannada", "October Meetei Mayek", "October Odia", "October Ol Chiki", "October Tamil", "October Telugu", "Optima", "Oriya MN", "Oriya Sangam MN", "Osaka", "Osaka-Mono",
      "Padyakke Expanded One", "Palatino", "Papyrus", "Party LET", "PCMyungjo", "Phosphate", "PilGi", "PingFang HK", "PingFang MO", "PingFang SC", "PingFang TC", "Plantagenet Cherokee", "PortagoITC TT", "Princetown LET", "Produkt", "Proxima Nova", "PSL Ornanong Pro", "PT Mono", "PT Sans", "PT Sans Caption", "PT Sans Narrow", "PT Serif", "PT Serif Caption", "Publico Headline", "Publico Text",
      "Quotes Caps", "Quotes Script",
      "Raanana", "Raya", "Rockwell",
      "Sama Devanagari", "Sama Gujarati", "Sama Gurmukhi", "Sama Kannada", "Sama Malayalam", "Sama Tamil", "Sana", "Santa Fe LET", "Sarabun", "Sathu", "Sauber Script", "Savoye LET", "Scheme", "SchoolHouse Cursive B", "SchoolHouse Printed A", "Seravek", "Shobhika", "Shree Devanagari 714", "SignPainter-HouseScript", "Silom", "SimSong", "Sinhala MN", "Sinhala Sangam MN", "Skia", "Snell Roundhand", "Somer", "Songti SC", "Songti TC", "Spot Mono", "Srisakdi", "STFangsong", "STHeiti", "STIXGeneral", "STIXIntegralsD", "STIXIntegralsSm", "STIXIntegralsUp", "STIXIntegralsUpD", "STIXIntegralsUpSm", "STIXNonUnicode", "STIXSizeFiveSym", "STIXSizeFourSym", "STIXSizeOneSym", "STIXSizeThreeSym", "STIXSizeTwoSym", "STIX Two Math", "STIX Two Text", "STIXVariants", "STKaiti", "STSong", "STXihei", "Stone Sans ITC TT", "Stone Sans Sem ITC TT", "Sukhumvit Set", "Superclarendon", "Symbol", "Synchro LET",
      "Tahoma", "Tamil MN", "Tamil Sangam MN", "Telugu MN", "Telugu Sangam MN", "The Hand Serif", "Thonburi", "Times", "Times New Roman", "Tiro Bangla", "Tiro Devanagari Hindi", "Tiro Devanagari Marathi", "Tiro Devanagari Sanskrit", "Tiro Gurmukhi", "Tiro Kannada", "Tiro Tamil", "Tiro Telugu", "Toppan Bunkyu Gothic", "Toppan Bunkyu Midashi Gothic", "Toppan Bunkyu Midashi Mincho", "Toppan Bunkyu Mincho", "Trattatello", "Trebuchet MS", "Tsukushi A Round Gothic", "Tsukushi B Round Gothic", "Tw Cen MT", "Type Embellishments One LET",
      "Verdana",
      "Waseem", "Wawati SC", "Wawati TC", "Webdings", "Weibei SC", "Weibei TC", "Wingdings", "Wingdings 2", "Wingdings 3",
      "Xingkai SC", "Xingkai TC",
      "Yaziji", "Yuanti SC", "Yuanti TC", "YuGothic", "YuKyokasho", "YuKyokasho Yoko", "YuMincho", "YuMincho +36p Kana", "Yuppy SC", "Yuppy TC",
      "Zapf Dingbats", "Zapfino", "Zawra"
    };
  } else if (platform == "linux") {
    return {
      // Ubuntu Font Family
      "Ubuntu", "Ubuntu Condensed", "Ubuntu Light", "Ubuntu Mono", "Ubuntu Sans", "Ubuntu Sans Mono",
      // DejaVu Family
      "DejaVu Sans", "DejaVu Sans Condensed", "DejaVu Sans Light", "DejaVu Sans Mono",
      "DejaVu Serif", "DejaVu Serif Condensed", "DejaVu Math TeX Gyre",
      // Liberation Family
      "Liberation Sans", "Liberation Sans Narrow", "Liberation Serif", "Liberation Mono",
      // Noto Family
      "Noto Sans", "Noto Sans Display", "Noto Sans Mono",
      "Noto Serif", "Noto Serif Display", "Noto Mono", "Noto Color Emoji",
      // Nimbus Family
      "Nimbus Sans", "Nimbus Sans L", "Nimbus Sans Narrow", "Nimbus Roman", "Nimbus Roman No9 L",
      "Nimbus Mono", "Nimbus Mono L", "Nimbus Mono PS",
      // FreeFont Family
      "FreeSans", "FreeSerif", "FreeMono"
    };
  }
  return {};
}

// 判断是否为基础字体（不应被处理）
static bool IsBasicFont(const std::string& font_family) {
  static constexpr const char* kBasicFonts[] = {
    // 系统特殊字体
    "-webkit-standard",
    "system-ui",

    // 基础西文字体
    "Arial",
    "Calibri",
    "Courier New",
    "Courier",
    "Helvetica",
    "Helvetica Neue",
    "Lucida Grande",
    "Microsoft Sans Serif",
    "MS Sans Serif",
    "MS Serif",
    "MS UI Gothic",
    "Roboto",
    "Sans",
    "Segoe UI",
    "Times New Roman",
    "Times",

    // CSS通用字体
    "cursive",
    "fantasy",
    "monospace",
    "sans-serif",
    "serif",
    "math",

    // 系统字体别名
    "BlinkMacSystemFont"
  };
   
  for (const char* f : kBasicFonts) {
     if (font_family == f) return true;
  }
  return basic_fonts.count(font_family) > 0;
}

const FontPlatformData* FontCache::GetFontPlatformData(
    const FontDescription& font_description,
    const FontFaceCreationParams& creation_params,
    AlternateFontName alternate_font_name) {
  TRACE_EVENT0("fonts", "FontCache::GetFontPlatformData");

  if (!platform_init_) {
    platform_init_ = true;
    PlatformInit();
  }

#if !BUILDFLAG(IS_MAC)
  if (creation_params.CreationType() == kCreateFontByFamily &&
      creation_params.Family() == font_family_names::kSystemUi) {
    return SystemFontPlatformData(font_description);
  }
#endif

  const base::CommandLine* command_line = base::CommandLine::ForCurrentProcess();
  // 字体指纹处理逻辑 - 不应用于最后手段字体
  if (command_line->HasSwitch(switches::kFingerprint) &&
      creation_params.CreationType() == kCreateFontByFamily &&
      alternate_font_name != AlternateFontName::kLastResort) {

    const std::string requested_family = creation_params.Family().Utf8();

    // 基础字体直接返回，不进行任何处理
    if (IsBasicFont(requested_family)) {
      return font_platform_data_cache_.GetOrCreateFontPlatformData(
          this, font_description, creation_params, alternate_font_name);
    }

    // 检测当前操作系统
    const char* current_os =
#if BUILDFLAG(IS_WIN)
      "windows";
#elif BUILDFLAG(IS_MAC)
      "macos";
#elif BUILDFLAG(IS_LINUX) || BUILDFLAG(IS_CHROMEOS)
      "linux";
#else
      "linux";  // 默认
#endif


    std::string spoofed_platform = command_line->GetSwitchValueASCII(switches::kFingerprintPlatform);
    if (spoofed_platform.empty()) {
      spoofed_platform = current_os;
    }

    std::vector<std::string> current_os_fonts = GetPlatformFonts(current_os);
    std::vector<std::string> platform_fonts = GetPlatformFonts(spoofed_platform);

    std::string fingerprint = command_line->GetSwitchValueASCII(switches::kFingerprint);
    uint32_t hash = std::hash<std::string>{}(fingerprint + requested_family);

    if (spoofed_platform != current_os) {
      // 获取伪装平台的字体列表
      bool is_platform_font = std::find(platform_fonts.begin(), platform_fonts.end(),
                                        requested_family) != platform_fonts.end();
      if (is_platform_font) {
        // 伪装平台的字体，用当前系统的字体替代
        size_t index = hash % current_os_fonts.size();
        FontFaceCreationParams substitute_params(AtomicString(current_os_fonts[index].c_str()));
        return font_platform_data_cache_.GetOrCreateFontPlatformData(
            this, font_description, substitute_params, alternate_font_name);
      } else {
        // 非平台字体处理：95%概率隐藏
        float probability = static_cast<float>(hash) / static_cast<float>(std::numeric_limits<uint32_t>::max());
        if (probability < 0.95) {
          return nullptr;
        }
        // 5%概率显示，继续默认流程
      }
    } else {
      // 系统相同，随机隐藏2%的字体以生成指纹
      float probability = static_cast<float>(hash) / static_cast<float>(std::numeric_limits<uint32_t>::max());
      if (probability < 0.02) {
        return nullptr;
      }
    }
  }

  return font_platform_data_cache_.GetOrCreateFontPlatformData(
      this, font_description, creation_params, alternate_font_name);
}

void FontCache::AcceptLanguagesChanged(const String& accept_languages) {
  LayoutLocale::AcceptLanguagesChanged(accept_languages);
}

const SimpleFontData* FontCache::GetFontData(
    const FontDescription& font_description,
    const AtomicString& family,
    AlternateFontName altername_font_name) {
  if (const FontPlatformData* platform_data = GetFontPlatformData(
          font_description,
          FontFaceCreationParams(
              AdjustFamilyNameToAvoidUnsupportedFonts(family)),
          altername_font_name)) {
    return FontDataFromFontPlatformData(
        platform_data, font_description.SubpixelAscentDescent());
  }

  return nullptr;
}

const SimpleFontData* FontCache::FontDataFromFontPlatformData(
    const FontPlatformData* platform_data,
    bool subpixel_ascent_descent) {
  return font_data_cache_.Get(platform_data, subpixel_ascent_descent);
}

bool FontCache::IsPlatformFamilyMatchAvailable(
    const FontDescription& font_description,
    const AtomicString& family) {
  return GetFontPlatformData(
      font_description,
      FontFaceCreationParams(AdjustFamilyNameToAvoidUnsupportedFonts(family)),
      AlternateFontName::kNoAlternate);
}

bool FontCache::IsPlatformFontUniqueNameMatchAvailable(
    const FontDescription& font_description,
    const AtomicString& unique_font_name) {
  // Return early to avoid attempting fallback.
  if (unique_font_name.empty()) {
    return false;
  }

  return GetFontPlatformData(font_description,
                             FontFaceCreationParams(unique_font_name),
                             AlternateFontName::kLocalUniqueFace);
}

String FontCache::FirstAvailableOrFirst(const String& families) {
  // The conversions involve at least two string copies, and more if non-ASCII.
  // For now we prefer shared code over the cost because a) inputs are
  // only from grd/xtb and all ASCII, and b) at most only a few times per
  // setting change/script.
  return String::FromUTF8(
      gfx::FontList::FirstAvailableOrFirst(families.Utf8().c_str()));
}

const SimpleFontData* FontCache::FallbackFontForCharacter(
    const FontDescription& description,
    UChar32 lookup_char,
    const SimpleFontData* font_data_to_substitute,
    FontFallbackPriority fallback_priority) {
  TRACE_EVENT0("fonts", "FontCache::FallbackFontForCharacter");

  // In addition to PUA, do not perform fallback for non-characters either. Some
  // of these are sentinel characters to detect encodings and do appear on
  // websites. More details on
  // http://www.unicode.org/faq/private_use.html#nonchar1 - See also
  // crbug.com/862352 where performing fallback for U+FFFE causes a memory
  // regression.
  if (Character::IsPrivateUse(lookup_char) ||
      Character::IsNonCharacter(lookup_char))
    return nullptr;
  base::ElapsedTimer timer;
  const SimpleFontData* result = PlatformFallbackFontForCharacter(
      description, lookup_char, font_data_to_substitute, fallback_priority);
  FontPerformance::AddSystemFallbackFontTime(timer.Elapsed());
  return result;
}

void FontCache::AddClient(FontCacheClient* client) {
  CHECK(client);
  DCHECK(!font_cache_clients_.Contains(client));
  font_cache_clients_.insert(client);
}

void FontCache::Invalidate() {
  TRACE_EVENT0("fonts,ui", "FontCache::Invalidate");
  font_platform_data_cache_.Clear();
  font_data_cache_.Clear();

  for (const auto& client : font_cache_clients_) {
    client->FontCacheInvalidated();
  }
}

void FontCache::CrashWithFontInfo(const FontDescription* font_description) {
  int num_families = std::numeric_limits<int>::min();

  num_families = skia::DefaultFontMgr()->countFamilies();

  FontDescription font_description_copy = *font_description;
  base::debug::Alias(&font_description_copy);
  base::debug::Alias(&num_families);

  NOTREACHED();
}

sk_sp<SkTypeface> FontCache::CreateTypefaceFromUniqueName(
    const FontFaceCreationParams& creation_params) {
  FontUniqueNameLookup* unique_name_lookup =
      FontGlobalContext::Get().GetFontUniqueNameLookup();
  DCHECK(unique_name_lookup);
  sk_sp<SkTypeface> uniquely_identified_font =
      unique_name_lookup->MatchUniqueName(creation_params.Family());
  if (uniquely_identified_font) {
    return uniquely_identified_font;
  }
  return nullptr;
}

// static
FontCache::Bcp47Vector FontCache::GetBcp47LocaleForRequest(
    const FontDescription& font_description,
    FontFallbackPriority fallback_priority) {
  Bcp47Vector result;

  // Fill in the list of locales in the reverse priority order.
  // Skia expects the highest array index to be the first priority.
  const LayoutLocale* content_locale = font_description.Locale();
  if (const LayoutLocale* han_locale =
          LayoutLocale::LocaleForHan(content_locale)) {
    result.push_back(han_locale->LocaleForHanForSkFontMgr());
  }
  result.push_back(LayoutLocale::GetDefault().LocaleForSkFontMgr());
  if (content_locale)
    result.push_back(content_locale->LocaleForSkFontMgr());

  if (IsEmojiPresentationEmoji(fallback_priority)) {
    result.push_back(kColorEmojiLocale);
  } else if (IsTextPresentationEmoji(fallback_priority)) {
    result.push_back(kMonoEmojiLocale);
  }
  return result;
}

// TODO(crbug/342967843): In WebTest, Fuchsia initializes fonts by calling
// `skia::InitializeSkFontMgrForTest();` expecting that other code doesn't
// initialize SkFontMgr beforehand. But `FontCache::MaybePreloadSystemFonts()`
// breaks this expectation. So we don't provide
// `FontCache::MaybePreloadSystemFonts()` feature for Fuchsia for now.
#if BUILDFLAG(IS_FUCHSIA)
// static
void FontCache::MaybePreloadSystemFonts() {}
#else
// static
void FontCache::MaybePreloadSystemFonts() {
  static bool initialized = false;
  if (initialized) {
    return;
  }

  initialized = true;
  CHECK(IsMainThread());

  if (!base::FeatureList::IsEnabled(features::kPreloadSystemFonts)) {
    return;
  }

  if (base::SysInfo::AmountOfPhysicalMemory().InGiB() <
      features::kPreloadSystemFontsRequiredMemoryGB.Get()) {
    return;
  }

  std::unique_ptr<JSONArray> targets =
      JSONArray::From(ParseJSON(String::FromUTF8(
          base::UnescapeURLComponent(features::kPreloadSystemFontsTargets.Get(),
                                     base::UnescapeRule::SPACES))));

  if (!targets) {
    return;
  }

  const LayoutLocale& locale = LayoutLocale::GetDefault();

  for (wtf_size_t i = 0; i < targets->size(); ++i) {
    JSONObject* target = JSONObject::Cast(targets->at(i));
    bool success = true;
    String family;
    success &= target->GetString("family", &family);
    int weight;
    success &= target->GetInteger("weight", &weight);
    double specified_size;
    success &= target->GetDouble("size", &specified_size);
    double computed_size;
    success &= target->GetDouble("csize", &computed_size);
    String text;
    success &= target->GetString("text", &text);
    if (success) {
      TRACE_EVENT("fonts", "PreloadSystemFonts", "family", family, "weight",
                  weight, "specified_size", specified_size, "computed_size",
                  computed_size, "text", text);
      FontDescription font_description;
      const AtomicString family_atomic_string(family);
      FontFamily font_family(family_atomic_string,
                             FontFamily::Type::kFamilyName);
      font_description.SetFamily(font_family);
      font_description.SetWeight(FontSelectionValue(weight));
      font_description.SetLocale(&locale);
      font_description.SetSpecifiedSize(
          base::saturated_cast<float>(specified_size));
      font_description.SetComputedSize(
          base::saturated_cast<float>(computed_size));
      font_description.SetGenericFamily(FontDescription::kSansSerifFamily);
      const SimpleFontData* simple_font_data =
          FontCache::Get().GetFontData(font_description, AtomicString(family));
      if (simple_font_data) {
        for (UChar32 c : text) {
          Glyph glyph = simple_font_data->GlyphForCharacter(c);
          std::ignore = simple_font_data->BoundsForGlyph(glyph);
        }
      }
    }
  }
}
#endif  // BUILDFLAG(IS_FUCHSIA)

FontFallbackMap& FontCache::GetFontFallbackMap() {
  if (!font_fallback_map_) {
    font_fallback_map_ = MakeGarbageCollected<FontFallbackMap>(nullptr);
    AddClient(font_fallback_map_);
  }
  return *font_fallback_map_;
}

}  // namespace blink
