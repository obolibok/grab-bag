SQL Test tasks  
Table ProjectActivity contains ProjectID of projects and modification Date for each project.  
1. Create SQL-query that calculates for each row how many consecutive days by this time each project was updated. First update we assume as 1 day in row.  
Expected result example:  

| Date | ProjectID | DaysInRow |
| --- | --- | --- |
| 2016-10-01 | 2 | 1 |
| 2016-10-01 | 1 | 1 |
| 2016-10-02 | 1 | 2 |
| 2016-10-02 | 3 | 1 |
| 2016-10-03 | 1 | 3 |
| 2016-10-05 | 1 | 1 |


2. Using data in table ProjectActivity create SQL-query that calculates metric “Abandoned 7” for each Date in table.  
Metric “Abandoned 7” defines percentage of projects (of overall modifications by day) which were updated this day but were not updated after 7 and more days.  
Example:  
At 2016-10-01 were updated Project 1 and Project 2. Project 1 has been updated next day and so on, Project 2 has not been modified anymore.  
“Abandoned 7” for date 2016-10-01 will be: count of abandoned projects / count of projects modified at 2016-10-01 * 100 % = 1 / 2 * 100 % = 50 %  
3. Using data in table ProjectActivity create SQL-query that calculates metric “Retention 7” for each Date in table.  
Metric “Retention 7” defines percentage of projects which were created 7 days ago and were updated this day (of total count of projects that created 7 days ago). Creation date is minimal modification Date for each project.
Example:  
At 2016-10-01 were created 10 projects. 3 of them were updated at 2016-10-08, other 7 were unchanged. “Retention 7” for 2016-10-01 will be: 3 / 10 * 100 % = 30 %.  
If at 2016-10-08 were updated other projects that created earlier of later than 2016-10-01 they shall not be used in calculation “Retention 7” for 2016-10-01. They should be used in calculation “Retention 7” for their creation date.  
Expected result example:  

| Date | Retention 7 |
| --- | --- |
| 2016-10-01 | 30% |
| 2016-10-02 | 50% |
| 2016-10-03 | 45% |

