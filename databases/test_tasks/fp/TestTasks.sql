SET STATISTICS IO ON;  
GO
declare @tmp table (ProjectID int not null, UpdateDate date not null)
insert into @tmp values (1, '2016-10-01'), (2, '2016-10-01'), (1, '2016-10-02'), (1, '2016-10-03'), (3, '2016-10-01'), (1, '2016-10-05'), (2, '2016-10-04'), (2, '2016-10-05'), (1, '2016-10-07'), (1, '2016-10-08'), (1, '2016-10-09'), (1, '2016-10-10')
;

/*with TMP as
   (select UpdateDate, ProjectID, case when datediff(dd,lag(UpdateDate, 1) over (partition by ProjectId order by UpdateDate),UpdateDate)=1 then 1 else 0 end as GRP
      from @tmp),
	XXX as (select UpdateDate, ProjectID, 1 as DaysInRow from TMP where GRP=0
	        union all
			select b.UpdateDate, b.ProjectID, a.DaysInRow+1 as DaysInRow from XXX a join TMP b on b.ProjectID=a.ProjectID and b.UpdateDate=dateadd(dd,1,a.UpdateDate))
select * from XXX
order by ProjectId, UpdateDate*/
GO
SET STATISTICS IO OFF;