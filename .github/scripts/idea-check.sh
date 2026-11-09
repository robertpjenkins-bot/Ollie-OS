#!/bin/bash
# Checks a recommendation (an issue whose title starts "Idea:") before it shows
# on the website's Recommendations tab. Reads TITLE and BODY from the
# environment; prints why it should be hidden, or nothing if it is fine.
# Used by .github/workflows/ideas.yml.
text=$(printf '%s\n%s\n' "${TITLE-}" "${BODY-}" | tr '[:upper:]' '[:lower:]')

has() { printf '%s\n' "$text" | grep -Eq -- "$1"; }

if has '[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}'; then
    echo "it has an email address"
elif has '(https?://|www\.|\b[a-z0-9-]+\.(com|net|org|io|gg|xyz|ru|ly)\b)'; then
    echo "it has a link"
elif has '(\(?[0-9]{3}\)?[ .-]?[0-9]{3}[ .-]?[0-9]{4})'; then
    echo "it has a phone number"
elif has '\b[0-9]+ [a-z]+ (street|st|road|rd|avenue|ave|drive|dr|lane|ln|court|ct|boulevard|blvd|way|place|pl)\b|\b(my|our) (address|phone|number|school is|password)\b|\bi live (at|on|in)\b'; then
    echo "it may have personal information"
elif has '\b(f+u+c+k+\w*|sh+i+t+\w*|bitch\w*|bastard|asshole|dick|piss\w*|crap|damn|slut|whore|cunt|porn\w*|sex\w*|nude\w*|stupid|idiot|loser|shut up)\b'; then
    echo "it has a rude word"
fi
