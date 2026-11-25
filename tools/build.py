#!/usr/bin/env python3
"""Build camp.html and motorhomes.html from src/site.html, and index.html from src/home.html.
Run from the repo root:  python3 tools/build.py"""
import re, pathlib
root = pathlib.Path(__file__).resolve().parent.parent
src = (root/'src/site.html').read_text()

NAV_CSS = '''
/* category nav */
.bar{display:block!important;padding:0!important}
.bar .in{display:flex;align-items:center;gap:10px;padding:10px 16px;max-width:1080px;margin:0 auto}
.cats{display:flex;gap:6px;overflow-x:auto;scrollbar-width:none;padding:0 16px 10px;max-width:1080px;margin:0 auto}
.cats::-webkit-scrollbar{display:none}
.cats a{flex:none;text-decoration:none;font-size:14.5px;font-weight:500;padding:7px 15px;border-radius:999px;border:1px solid #fff;background:#fff;color:var(--ink);white-space:nowrap;min-height:38px;display:inline-flex;align-items:center;box-shadow:0 1px 3px rgba(0,0,0,.12)}
.bar.solid .cats a{border-color:var(--line)}
.cats a[aria-current=page]{background:var(--sage);color:#fff;border-color:var(--sage)}
html{scroll-padding-top:120px}
'''
def header(cur):
    a=lambda href,key: f'<a href="{href}" data-t="{key}"{" aria-current=\"page\"" if key==cur else ""}></a>'
    return ('<header class="bar" id="bar">\n  <div class="in">\n    <a class="brand" href="index.html">Ozora Camp</a>\n'
            '    <div class="lang" role="group" aria-label="Language"><button data-l="he" aria-pressed="true"><span>עב</span></button><button data-l="en" aria-pressed="false"><span>EN</span></button></div>\n'
            '    <a class="cta" href="{BOOK}" data-t="bookNow">הזמנה</a>\n  </div>\n'
            f'  <nav class="cats" aria-label="categories">{a("index.html","nHome")}{a("camp.html","nCamp")}{a("motorhomes.html","nRv")}</nav>\n</header>')

def common(s, cur, book):
    s = re.sub(r'<header class="bar" id="bar">.*?</header>', header(cur).replace('{BOOK}',book), s, count=1, flags=re.S)
    s = s.replace('</style>', NAV_CSS+'</style>', 1)
    s = s.replace("he:{dir:'rtl',", "he:{dir:'rtl',nHome:'בית',nCamp:'לינה במתחם',nRv:'קרוואנים ממונעים',", 1)
    s = s.replace("en:{dir:'ltr',", "en:{dir:'ltr',nHome:'Home',nCamp:'Stay at the camp',nRv:'Motorhomes',", 1)
    return s

# ---- camp.html: everything except the motorhome section
camp = common(src, 'nCamp', '#book')
camp = camp.replace('<section id="rv">', '<section id="rv" hidden>', 1)
camp = camp.replace('<meta property="og:url" content="https://vivi-aviel.github.io/ozora-camp/">','<meta property="og:url" content="https://vivi-aviel.github.io/ozora-camp/camp.html">',1)
(root/'camp.html').write_text(camp)

# ---- motorhomes.html: only the motorhome section
rv = common(src, 'nRv', '#rvf')
HIDE = '\n.page-rv #stay,.page-rv .facts,.page-rv #gallery,.page-rv #map,.page-rv #around,.page-rv #book,.page-rv #info,.page-rv #float{display:none!important}\n.page-rv .hero{min-height:70vh;min-height:70svh}\n.page-rv #rv>h2,.page-rv #rv>.lead{display:none}\n.page-rv main{padding-top:8px}\n'
rv = rv.replace('</style>', HIDE+'</style>', 1)
rv = rv.replace('<body>', '<body class="page-rv">', 1)
rv = re.sub(r'<img src="assets/img/lake.jpg"[^>]*>', '<img src="assets/img/rv/big1.jpg" alt="" fetchpriority="high">', rv, count=1)
rv = rv.replace('<h1>Ozora Camp</h1>', '<h1 data-t="rvH1"></h1>', 1)
rv = re.sub(r'(<div class="hero" id="top">.*?)<p data-t="heroText"></p>', r'\1<p data-t="rvHeroP"></p>', rv, count=1, flags=re.S)
rv = re.sub(r'(<div class="hero" id="top">.*?)<div class="row"><a class="cta" href="#book" data-t="checkDates"></a><a class="ghost" href="#stay" data-t="seeRooms"></a></div>',
            r'\1<div class="row"><a class="cta" href="#rvf" data-t="rvHeroBtn"></a><a class="ghost" href="#rv" data-t="rvHeroBtn2"></a></div>', rv, count=1, flags=re.S)
rv = rv.replace("he:{dir:'rtl',", "he:{dir:'rtl',rvH1:'קרוואנים ממונעים',rvHeroP:'אוספים, נוהגים וישנים בו בפסטיבל OZORA. קרוואן ל־6 וקרוואן ל־3 – מאובזרים ועצמאיים, עם ביטוח מקיף.',rvHeroBtn:'בדיקת מחיר ובקשה',rvHeroBtn2:'לקרוואנים',", 1)
rv = rv.replace("en:{dir:'ltr',", "en:{dir:'ltr',rvH1:'Motorhomes',rvHeroP:'Pick it up, drive it and sleep in it at OZORA Festival. One for 6 and one for 3 – fully equipped, self-sufficient and fully insured.',rvHeroBtn:'Price & request',rvHeroBtn2:'See the motorhomes',", 1)
rv = rv.replace("title:'Ozora Camp – לינה ליד פסטיבל אוזורה'", "title:'קרוואנים ממונעים לפסטיבל אוזורה – Ozora Camp'", 1)
rv = rv.replace("title:'Ozora Camp – stay next to OZORA Festival'", "title:'Motorhomes for OZORA Festival – Ozora Camp'", 1)
rv = re.sub(r'<title>.*?</title>', '<title>קרוואנים ממונעים לפסטיבל אוזורה – Ozora Camp</title>', rv, count=1)
rv = re.sub(r'<meta property="og:url"[^>]*>', '<meta property="og:url" content="https://vivi-aviel.github.io/ozora-camp/motorhomes.html">', rv, count=1)
rv = re.sub(r'<meta property="og:title"[^>]*>', '<meta property="og:title" content="קרוואנים ממונעים להשכרה – פסטיבל אוזורה">', rv, count=1)
rv = re.sub(r'<meta property="og:description"[^>]*>', '<meta property="og:description" content="נוסעים איתו לפסטיבל וישנים בו. קרוואן ל־6 וקרוואן ל־3, מאובזרים, עם ביטוח מקיף. בדקו מחיר ושלחו בקשה.">', rv, count=1)
rv = rv.replace('assets/img/share6.jpg', 'assets/img/share-rv.jpg')
rv = re.sub(r'<meta name="description"[^>]*>', '<meta name="description" content="השכרת קרוואנים ממונעים לפסטיבל אוזורה בהונגריה: קרוואן ל־6 וקרוואן ל־3, מאובזרים ועצמאיים, עם ביטוח מקיף.">', rv, count=1)
(root/'motorhomes.html').write_text(rv)

# ---- index.html: the home page with categories
(root/'index.html').write_text((root/'src/home.html').read_text())
print('built index.html, camp.html, motorhomes.html')
