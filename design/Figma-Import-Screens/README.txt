Ishara - screens for Figma (17 screens, 390 x 844)

How to use (Ubuntu):
1. Unzip this folder anywhere, e.g. ~/Documents/figma-screens
2. Open index.html in Google Chrome (double-click, or: google-chrome index.html)
3. Chrome -> Extensions -> html.to.design -> Details -> turn ON "Allow access to file URLs"
   (needed because the pages open from your disk, not from a website)
4. Open a screen, click the html.to.design icon, Capture, then Import it with the
   html.to.design plugin inside Figma.

If the extension refuses file:// pages, run a tiny local server instead:
   cd ~/Documents/figma-screens
   python3 -m http.server 8790
   then open http://localhost:8790 in Chrome.
