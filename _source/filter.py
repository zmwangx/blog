#!/usr/bin/env python3

import copy
import sys

import bs4


def transform_sidenotes(soup):
    # Example sidenote:
    #
    #   <label for="sn-extensive-use-of-sidenotes" class="margin-toggle sidenote-number"></label>
    #   <input type="checkbox" id="sn-extensive-use-of-sidenotes" class="margin-toggle">
    #   <span class="sidenote">This is a sidenote.</span>
    for sidenote in soup.select("sidenote"):
        label = soup.new_tag(
            "label", **{"for": sidenote["id"], "class": "margin-toggle sidenote-number"}
        )
        input_ = soup.new_tag(
            "input",
            **{"type": "checkbox", "id": sidenote["id"], "class": "margin-toggle"}
        )
        span = soup.new_tag("span", **{"class": "sidenote"})
        for elem in sidenote.contents:
            span.append(copy.copy(elem))

        sidenote.replace_with(label)
        label.insert_after(input_)
        input_.insert_after(span)


def main():
    soup = bs4.BeautifulSoup(sys.stdin.read(), "html5lib")
    transform_sidenotes(soup)
    sys.stdout.write(str(soup))


if __name__ == "__main__":
    main()
