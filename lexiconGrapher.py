import re
from sgmllib import SGMLParser
import sys
import urllib

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

def cleanURL(url):
    url = re.sub('\+27', "'", url)
    url = re.sub('\+2d', "-", url)
    url = re.sub('\+2c', ",", url)
    url = re.sub('_', " ", url)
    return url
    
def findURLs(urls):
    matches = [ re.match(pattern, x) for x in urls ]
    dematched = [ x.group(1) for x in matches if x != None ]
    dematched = filter (lambda x : x not in proscribedEntries, dematched)
    return dematched

def processEntries(entries, name):
    done = []
    for entry in entries:
        if ((entry not in proscribedEntries) and
                (entry not in done) and
                (entry != name)):
            outputFile.write('"' + cleanURL(name) + '" -> "' +
                    cleanURL(entry) + '"\n')
            done.append(entry)

base = "http://www.saturnvalley.org"
indexCutoff = "/lexicon/Timeline"

outputFile = sys.stdout
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

entries = findURLs(indexUrls)
#processEntries(entries, "Index") # On second thought, maybe not.
for e in entries:
    outputFile.write('"' + cleanURL(e) + '" [href="/lexicon/' + e + '"]\n')
    page = urllib.urlopen(base + "/lexicon/" + e)
    parser.feed(page.read())
    page.close()
    parser.close()
    links = findURLs(parser.urls)
    processEntries(links, e)
    parser.reset()

outputFile.write("}")
outputFile.close()
