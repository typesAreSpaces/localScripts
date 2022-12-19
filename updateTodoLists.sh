#!/bin/sh

cd $PHD_DOCUMENTS; git add *.org
cd $PHD_DOCUMENTS/Seminars/BeihangUniversity-Fall2021/Org-Files/; git add *.org
cd $PHD_DOCUMENTS/Side-Projects/MaxDiff/Documents/org/; git add *.org
cd $PHD_DOCUMENTS/Semesters/Spring/2022/TA-CS-429-529/Org-Files/; git add *.org
cd $PHD_DOCUMENTS/Side-Projects/kapur-nsf-proposal/Org-Files/; git add *.org
cd $PHD_DOCUMENTS; git commit -m "Update Org-Files."
