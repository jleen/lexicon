import re
import urllib
from sgmllib import SGMLParser

# You know, on second thought, it would probably have been healthier to parse the whole mess into a data structure. Then I could have done more subtle things with it, like signal the differences between phantoms and nonphantoms on a second pass through the data structure. Maybe in an upgrade.
class URLGetter(SGMLParser):
  def reset(self):
    SGMLParser.reset(self)
    self.urls = []

  def start_a(self,attrs):
    href = [v for k, v in attrs if k == 'href']
    if href:
      self.urls.extend(href)

pattern = re.compile("/lexicon/([^/?]*)$")
proscribedEntries = ["Index", "UserPreferences", "SiteNavigation", "Welcome", "RecentChanges", "FindPage", "HelpContents"]

def cleanURLs(urls):
    matches = map((lambda x : re.match(pattern, x)), urls)
    matches = filter(lambda x : (not (x == None)), matches)
    dematched = map(lambda x : x.group(1), matches)
    dematched = map(lambda entry : re.sub('\+27', "'", entry), dematched)
    dematched = map(lambda entry : re.sub('\+2d', "-", entry), dematched)
    dematched = map(lambda entry : re.sub('\+2c', ",", entry), dematched)
    dematched = filter (lambda x : x not in proscribedEntries, dematched)
    return dematched

def processEntries(entries, name):
    done = []
    for entry in entries:
        if ((entry not in proscribedEntries) and (entry not in done) and  (entry != name)):
            outputFile.write(name + " -> " + entry + "\n")
            done.append(entry)

base = "http://www.saturnvalley.org"
indexCutoff = "/lexicon/Timeline"

outputFile = file("lexiconGraph", "w")
outputFile.write("digraph lexicon {\n")

parser = URLGetter()

indexSock = urllib.urlopen(base + "/lexicon/Index");
parser.feed(indexSock.read())
indexSock.close()
parser.close()
indexUrls = parser.urls
found = 0;
while(not found):
    if (indexUrls.pop(0) == indexCutoff):
        found = 1
parser.reset()

entries = cleanURLs(indexUrls)
#processEntries(entries, "Index") # On second thought, maybe not.
for e in entries:
    print e
    page = urllib.urlopen(base + "/lexicon/" + e)
    parser.feed(page.read())
    page.close()
    parser.close()
    links = cleanURLs(parser.urls)
    processEntries(links, e)
    parser.reset()

outputFile.write("}")
outputFile.close()
