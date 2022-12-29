#!/bin/sh

cd $PHD_DOCUMENTS/Org-Files
git add *.org
cd $PHD_DOCUMENTS/Seminars/BeihangUniversity-Fall2021/Org-Files
git add *.org
cd $PHD_DOCUMENTS/Semesters/Spring/2023/TA-CS-357/Org-Files
git add *.org
cd $PHD_DOCUMENTS/Side-Projects/MaxDiff/Documents/org
git add *.org
cd $PHD_DOCUMENTS
git commit -m "Update Org-Files."
