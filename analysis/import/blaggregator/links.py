import os
import requests
from lxml import etree

incoming_count = 0
bad_connection = []
bad_status = []
bad_xml = []
bad_feed = []
empty_feed = []
success_count = 0

if os.path.exists('links.csv'):
    os.remove('links.csv')

with open('rss.csv', encoding='utf-8') as rss_f:
    for i, line in enumerate(rss_f):
        incoming_count += 1

        (rss_url, comment) = line.strip().split(';')
        print(i, rss_url)
        try:
            response = requests.get(rss_url)
        except requests.exceptions.ConnectionError as e:
            bad_connection.append(rss_url)
            print(e)
            continue
        
        if response.status_code != 200:
            bad_status.append(rss_url)
            print(response.status_code)
            continue
        
        try:
            root = etree.fromstring(response.content)
        except etree.XMLSyntaxError as e:
            bad_xml.append(rss_url)
            print(e)
            continue

        if root.tag == 'rss':
            posts = root.xpath('channel/item')
            if len(posts) == 0:
                empty_feed.append(rss_url)
                print("Empty RSS")
                continue
            
            channel_links = root.xpath('channel/link')
            channel_alternate_links = [link for link in channel_links if 'rel' not in link.attrib or link.attrib['rel'] == 'alternate']
            if len(channel_alternate_links) != 1:
                breakpoint()
                channel_alternate_links = channel_links
            
            link = channel_alternate_links[0].text

        elif root.tag == '{http://www.w3.org/2005/Atom}feed':
            namespaces = {'atom':'http://www.w3.org/2005/Atom'}
            posts = root.xpath('//atom:entry', namespaces=namespaces)
            if len(posts) == 0:
                empty_feed.append(rss_url)
                print("Empty Atom")
                continue

            channel_links = root.xpath('atom:link', namespaces=namespaces)
            channel_alternate_links = [link for link in channel_links if 'rel' not in link.attrib or link.attrib['rel'] == 'alternate']
            if len(channel_alternate_links) != 1:
                breakpoint()
                channel_alternate_links = channel_links

            link = channel_alternate_links[0].attrib['href']

        else:
            bad_feed.append(rss_url)
            print("Bad feed")
            print(response.text[:250])
            continue

        success_count += 1
        print(f'Success {link}')
        with open('links.csv', 'a', encoding='utf-8') as links_f:
            links_f.write(f'{link};{comment}\n')

# Handled:
# Connection failures
# Bad status codes
# Redirects (by requests itself)
# RSS and Atom
# No posts in feed

# Not handled:
# No alternate link
# Empty link
# Relative link
# Formatted xml
# RSS that is atom
# Invalid link "//ldirer.com/"
# No http <link>amandinemlee.com</link>
# Valid xml but invalid rss http://sahatyalkabov.com/feed


print('bad_connection:', bad_connection)
print('bad_status:', bad_status)
print('bad_xml:', bad_xml)
print('bad_feed:', bad_feed)
print('empty_feed:', empty_feed)

print('incoming_count:', incoming_count)
print('bad_connection_count:', len(bad_connection))
print('bad_status_count:', len(bad_status))
print('bad_xml_count:', len(bad_xml))
print('bad_feed_count:', len(bad_feed))
print('empty_feed_count:', len(empty_feed))
print('success_count:', success_count)
