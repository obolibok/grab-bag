USE [target_db]
GO

  set nocount on
  
  declare @src nvarchar(200), @limit nvarchar(max) = null, @step int = 0
  select @src = '[server_name].[db_name]', @limit='~DEBUG_MailLog~LOG_Requests~LOG_Errors~QRTZ_ExecutionHistoryEntries~', @step=0

  if @step=0 begin /* create working table */
    create table dbp_level1 (id int not null identity(1,1) primary key, obj_type nvarchar(10) not null, obj_id int not null, obj_full_name nvarchar(max), obj_schema nvarchar(200), obj_name nvarchar(200), obj_creation nvarchar(max), obj_data nvarchar(max), obj_success int not null default(0), obj_rows bigint)
  end

  declare @obj_id int, @obj_name nvarchar(200), @id int
  declare @qry nvarchar(max), @qry_out nvarchar(max)

  /* template for data copying with identity column, top and ord clauses is necessary to not copy big tables */
  declare @templateIdentity nvarchar(max) = '
  SET IDENTITY_INSERT ~TableName~ ON
  insert into ~TableName~ (~Columns~) select ~TOP~ ~Columns~ from '+@src+'.~TableName~ ~ORD~
  SET IDENTITY_INSERT ~TableName~ OFF'
  /* template for data copying without identity column */
  declare @templateNoIdentity nvarchar(max) = 'insert into ~TableName~ (~Columns~) select ~TOP~ ~Columns~ from '+@src+'.~TableName~ ~ORD~'

  if @step<=1 begin /* collect all tables from source DB */
    set @qry = 'insert into dbp_level1 (obj_type, obj_id, obj_full_name, obj_schema, obj_name)
                  select ''TBL'', obj.object_id, ''[''+sch.name+''].[''+obj.name+'']'', sch.name, obj.name
                  from '+@src+'.sys.objects obj
                    join '+@src+'.sys.schemas sch on sch.schema_id=obj.schema_id
                  where obj.type=''U''
                  order by obj.name'
    exec (@qry)

    set @qry = 'insert into dbp_level1 (obj_type, obj_id, obj_full_name, obj_schema, obj_name, obj_creation)
                  select ''SCH'', src.schema_id, ''[''+src.name+'']'', src.name, src.name, ''create schema [''+src.name+'']''
                  from '+@src+'.sys.schemas src
                    left join sys.schemas dst on dst.name COLLATE SQL_Latin1_General_CP1_CI_AS = src.name COLLATE SQL_Latin1_General_CP1_CI_AS
                  where dst.name is null'
    exec (@qry)
  end

  if @step<=2 begin /* loop for structure creating and data copy */
    begin /* create schemas if not exist */
      declare cur1 cursor local static forward_only for select id, obj_creation from dbp_level1 where obj_type='SCH' order by id
      open cur1
      fetch next from cur1 into @id, @qry
      while @@FETCH_STATUS=0 begin
        exec (@qry)
        update dbp_level1 set obj_success=obj_success+1 where id=@id
        fetch next from cur1 into @id, @qry
      end
      close cur1
      deallocate cur1
    end
    declare cur1 cursor local static forward_only for select id, obj_id, obj_full_name from dbp_level1 where obj_type='TBL' order by id
    open cur1
    fetch next from cur1 into @id, @obj_id, @obj_name
    while @@FETCH_STATUS=0 begin
      if @step<=1 begin /* build create table query, store it and execute */
        set @qry='select @qry_out=''create table ''+@obj_name+'' (''+replace(replace((
            select ''"[''+col.name+''] ''
                  +case when col.is_computed=0 then typ.name else '''' end
                  +case when col.is_computed=0 and typ.name in (''varchar'',''char'',''nchar'',''nvarchar'',''varbinary'',''binary'') then ''(''+case when col.max_length<0 then ''max'' when left(typ.name,1)=''N'' then cast(col.max_length/2 as nvarchar(20)) else cast(col.max_length as nvarchar(20)) end+'')'' else '''' end
                  +case when col.is_computed=1 or col.is_nullable=1 then '''' else '' not null'' end
                  +case when col.is_identity=1 then '' identity(1,1)'' else '''' end
                  +case when col.is_computed=1 then ''as ''+com.[definition] + case when com.is_persisted=1 then '' persisted'' else '''' end else '''' end
                  +''"'' as ''data()''
              from '+@src+'.sys.objects obj
                join '+@src+'.sys.columns col on col.object_id=obj.object_id
                join '+@src+'.sys.types typ on typ.user_type_id=col.user_type_id
                left join '+@src+'.sys.computed_columns com on com.object_id=col.object_id and com.column_id=col.column_id
              where obj.Type=''U''
                and obj.object_id=@obj_id
              order by col.column_id
              for xml path('''')
        ),''" "'',''", "''),''"'','''')+'')'''
        exec sp_executesql @qry, N'@obj_id int, @obj_name nvarchar(max), @qry_out nvarchar(max) OUTPUT', @obj_id=@obj_id, @obj_name=@obj_name,  @qry_out=@qry_out OUTPUT
        update dbp_level1 set obj_creation=@qry_out where id=@id
        exec (@qry_out)
        update dbp_level1 set obj_success=obj_success+1 where id=@id
      end
      if @step<=2 begin /* build data copy query, store it and execute */
        set @qry='select @qry_out=replace(replace(replace(replace(case when IsIdentity=1 then @templateIdentity else @templateNoIdentity end, ''~TableName~'', TabFullName),''~Columns~'',Cols),''~TOP~'',case when @limit like ''%~''+TabName+''~%'' then ''TOP 0 '' else '''' end),''~ORD~'',case when @limit like ''%~''+TabName+''~%'' and IDC is not null then ''order by [''+IDC+''] desc'' else '''' end)
      from (
        select case when idc.name is null then 0 else 1 end as IsIdentity,
               ''[''+shm.name+''].[''+tbl.name+'']'' as TabFullName,
               replace(replace((select ''"[''+col.name+'']"'' as ''data()'' from '+@src+'.sys.columns col where col.[object_id]=tbl.[object_id] and col.is_computed=0 and col.system_type_id!=189 /* timestamp cannot be copied */ order by col.name for xml path('''')),''" "'',''", "''),''"'','''') as Cols,
               tbl.name as TabName,
               idc.name as IDC
          from '+@src+'.sys.objects tbl
            join '+@src+'.sys.schemas shm on shm.[schema_id]=tbl.[schema_id]
            left join '+@src+'.sys.columns idc on idc.[object_id]=tbl.[object_id] and idc.is_identity=1
          where tbl.object_id=@obj_id) dat'
        exec sp_executesql @qry, N'@obj_id int, @templateIdentity nvarchar(max), @templateNoIdentity nvarchar(max), @limit nvarchar(max), @qry_out nvarchar(max) OUTPUT', @obj_id=@obj_id, @templateIdentity=@templateIdentity, @templateNoIdentity=@templateNoIdentity, @limit=@limit, @qry_out=@qry_out OUTPUT
        update dbp_level1 set obj_data=@qry_out where id=@id
        exec (@qry_out)
        update dbp_level1 set obj_success=obj_success+2, obj_rows=@@ROWCOUNT where id=@id
      end
      fetch next from cur1 into @id, @obj_id, @obj_name
    end
    close cur1
    deallocate cur1
  end

  if @step<=3 begin /* collect all defaults from source DB */
    set @qry = 'insert into dbp_level1 (obj_type, obj_id, obj_full_name, obj_schema, obj_name, obj_creation)
                  select ''DEF'',obj.object_id, ''[''+sch.name+''].[''+obj.name+'']'', sch.name, obj.name,
                      ''ALTER TABLE [''+sch.name+''].[''+obj.name+''] ADD CONSTRAINT [''+con.[name]+''] DEFAULT ''+con.[definition]+'' FOR [''+col.[name]+'']''
                    from '+@src+'.sys.objects obj
                      join '+@src+'.sys.schemas sch on sch.schema_id=obj.schema_id
                      join '+@src+'.sys.all_columns col on col.object_id=obj.object_id
                      left join '+@src+'.sys.default_constraints con on con.parent_object_id = obj.object_id and con.parent_column_id = col.column_id
                    where obj.type=''U'' and con.object_id is not null
                    order by obj.name'
    exec (@qry)
  end

  if @step<=3 begin /* loop for defaults */
    declare cur1 cursor local static forward_only for select id, obj_creation from dbp_level1 where obj_type='DEF' order by id
    open cur1
    fetch next from cur1 into @id, @qry_out
    while @@FETCH_STATUS=0 begin
      /* create default */
      exec (@qry_out)
      update dbp_level1 set obj_success=obj_success+1 where id=@id
      
      fetch next from cur1 into @id, @qry_out
    end
    close cur1
    deallocate cur1
  end

  if @step<=4 begin /* collect all PKs from source DB */
    set @qry='insert into dbp_level1 (obj_type, obj_id, obj_full_name, obj_schema, obj_name, obj_creation)
                select ''PK'', obj.object_id, ''[''+sch.name+''].[''+obj.name+'']'', sch.name, obj.name,
                   ''ALTER TABLE [''+sch.name+''].[''+obj.name+''] ADD CONSTRAINT [''+idx.[name]+''] PRIMARY KEY ''+case when idx.type=1 then ''CLUSTERED'' when idx.type=2 then ''NONCLUSTERED'' else '''' end+''(''+
                   replace(replace((select ''"[''+col.name+'']''+case when ico.is_descending_key=1 then '' DESC'' else '''' end+''"'' as ''data()''
                                      from '+@src+'.sys.index_columns ico
                                        join '+@src+'.sys.columns col on col.object_id=ico.object_id and col.column_id=ico.column_id
                                      where ico.object_id=obj.object_id and ico.index_id=idx.index_id
                                      order by ico.index_column_id
                   for xml path('''')),''" "'',''", "''),''"'','''')+'')''
                  from '+@src+'.sys.objects obj
                    join '+@src+'.sys.schemas sch on sch.schema_id=obj.schema_id
                    join '+@src+'.sys.indexes idx on idx.object_id=obj.object_id and idx.is_primary_key=1
                  where obj.type=''U''
                  order by obj.name'
    exec (@qry)
  end

  if @step<=4 begin /* loop for PKs */
    declare cur1 cursor local static forward_only for select id, obj_creation from dbp_level1 where obj_type='PK' order by id
    open cur1
    fetch next from cur1 into @id, @qry_out
    while @@FETCH_STATUS=0 begin
      /* create default */
      exec (@qry_out)
      update dbp_level1 set obj_success=obj_success+1 where id=@id
      
      fetch next from cur1 into @id, @qry_out
    end
    close cur1
    deallocate cur1
  end

  if @step<=5 begin /* collect all UKs from source DB */
    set @qry='insert into dbp_level1 (obj_type, obj_id, obj_full_name, obj_schema, obj_name, obj_creation)
                select ''UK'', obj.object_id, ''[''+sch.name+''].[''+obj.name+'']'', sch.name, obj.name,
                   ''ALTER TABLE [''+sch.name+''].[''+obj.name+''] ADD CONSTRAINT [''+idx.[name]+''] UNIQUE ''+case when idx.type=1 then ''CLUSTERED'' when idx.type=2 then ''NONCLUSTERED'' else '''' end+'' (''+
                   replace(replace((select ''"[''+col.name+'']''+case when ico.is_descending_key=1 then '' DESC'' else '''' end+''"'' as ''data()''
                                      from '+@src+'.sys.index_columns ico
                                        join '+@src+'.sys.columns col on col.object_id=ico.object_id and col.column_id=ico.column_id
                                      where ico.object_id=obj.object_id and ico.index_id=idx.index_id
                                      order by ico.index_column_id
                   for xml path('''')),''" "'',''", "''),''"'','''')+'')''
                  from '+@src+'.sys.objects obj
                    join '+@src+'.sys.schemas sch on sch.schema_id=obj.schema_id
                    join '+@src+'.sys.indexes idx on idx.object_id=obj.object_id and idx.is_unique_constraint=1
                  where obj.type=''U''
                  order by obj.name'
    exec (@qry)
  end

  if @step<=5 begin /* loop for UKs */
    declare cur1 cursor local static forward_only for select id, obj_creation from dbp_level1 where obj_type='UK' order by id
    open cur1
    fetch next from cur1 into @id, @qry_out
    while @@FETCH_STATUS=0 begin
      /* create default */
      exec (@qry_out)
      update dbp_level1 set obj_success=obj_success+1 where id=@id
      
      fetch next from cur1 into @id, @qry_out
    end
    close cur1
    deallocate cur1
  end

  if @step<=6 begin /* collect all FKs from source DB */
    set @qry='insert into dbp_level1 (obj_type, obj_id, obj_full_name, obj_schema, obj_name, obj_creation)
                select ''FK'', obj.object_id, ''[''+sch.name+''].[''+obj.name+'']'', sch.name, obj.name,
                   ''ALTER TABLE [''+sch.name+''].[''+obj.name+''] ADD CONSTRAINT [''+fks.[name]+''] FOREIGN KEY (''+
                   replace(replace((select ''"[''+ocl.name+'']"'' as ''data()''
                                      from '+@src+'.sys.foreign_key_columns fcl
                                        join '+@src+'.sys.columns ocl on ocl.object_id=fcl.parent_object_id and ocl.column_id=fcl.parent_column_id
                                      where fcl.constraint_object_id=fks.object_id
                                      order by fcl.constraint_column_id
                                      for xml path('''')),''" "'',''", "''),''"'','''')+'') REFERENCES [''+rch.name+''].[''+rbj.name+''] (''+
                   replace(replace((select ''"[''+rcl.name+'']"'' as ''data()''
                                      from '+@src+'.sys.foreign_key_columns fcl
                                        join '+@src+'.sys.columns rcl on rcl.object_id=fcl.referenced_object_id and rcl.column_id=fcl.referenced_column_id
                                      where fcl.constraint_object_id=fks.object_id
                                      order by fcl.constraint_column_id
                                      for xml path('''')),''" "'',''", "''),''"'','''')+'')''+case when fks.delete_referential_action=1 then '' ON DELETE CASCADE'' else '''' end+case when fks.update_referential_action=1 then '' ON UPDATE CASCADE'' else '''' end
                  from '+@src+'.sys.objects obj
                    join '+@src+'.sys.schemas sch on sch.schema_id=obj.schema_id
                    join '+@src+'.sys.foreign_keys fks on fks.parent_object_id=obj.object_id
                    join '+@src+'.sys.objects rbj on rbj.object_id=fks.referenced_object_id
                    join '+@src+'.sys.schemas rch on rch.schema_id=rbj.schema_id
                  where obj.type=''U''
                  order by obj.name'
    exec (@qry)
  end

  if @step<=6 begin /* loop for FKs */
    declare cur1 cursor local static forward_only for select id, obj_creation from dbp_level1 where obj_type='FK' order by id
    open cur1
    fetch next from cur1 into @id, @qry_out
    while @@FETCH_STATUS=0 begin
      /* create default */
      exec (@qry_out)
      update dbp_level1 set obj_success=obj_success+1 where id=@id
      
      fetch next from cur1 into @id, @qry_out
    end
    close cur1
    deallocate cur1
  end

  if @step<=7 begin /* collect all IXs from source DB */
    set @qry='insert into dbp_level1 (obj_type, obj_id, obj_full_name, obj_schema, obj_name, obj_creation)
                select ''IX'', obj.object_id, ''[''+sch.name+''].[''+obj.name+'']'', sch.name, obj.name,
                    ''CREATE ''+case when idx.is_unique=1 then ''UNIQUE '' else '''' end+case when idx.type=1 then ''CLUSTERED '' when idx.type=2 then ''NONCLUSTERED '' else '''' end+'' INDEX [''+idx.[name]+''] ON [''+sch.name+''].[''+obj.name+''] (''+
                    replace(replace((select ''"[''+col.name+'']''+case when ico.is_descending_key=1 then '' DESC'' else '''' end+''"'' as ''data()''
                                       from '+@src+'.sys.index_columns ico
                                         join '+@src+'.sys.columns col on col.object_id=ico.object_id and col.column_id=ico.column_id
                                       where ico.object_id=obj.object_id and ico.index_id=idx.index_id and ico.is_included_column=0
                                       order by ico.index_column_id
                                   for xml path('''')),''" "'',''", "''),''"'','''')+'')''+
                    isnull('' INCLUDE (''+replace(replace((select ''"[''+col.name+'']''+case when ico.is_descending_key=1 then '' DESC'' else '''' end+''"'' as ''data()''
                                       from '+@src+'.sys.index_columns ico
                                         join '+@src+'.sys.columns col on col.object_id=ico.object_id and col.column_id=ico.column_id
                                       where ico.object_id=obj.object_id and ico.index_id=idx.index_id and ico.is_included_column=1
                                       order by ico.index_column_id
                                   for xml path('''')),''" "'',''", "''),''"'','''')+'')'','''')+isnull('' WHERE ''+idx.filter_definition,'''')
                  from '+@src+'.sys.objects obj
                    join '+@src+'.sys.schemas sch on sch.schema_id=obj.schema_id
                    join '+@src+'.sys.indexes idx on idx.object_id=obj.object_id and idx.is_unique_constraint<>1 and idx.is_primary_key<>1 and idx.index_id>0
                  where obj.type=''U''
                  order by obj.name'
    exec (@qry)
  end

  if @step<=7 begin /* loop for IXs */
    declare cur1 cursor local static forward_only for select id, obj_creation from dbp_level1 where obj_type='IX' and obj_success=0 order by id
    open cur1
    fetch next from cur1 into @id, @qry_out
    while @@FETCH_STATUS=0 begin
      /* create default */
      exec (@qry_out)
      update dbp_level1 set obj_success=obj_success+1 where id=@id
      
      fetch next from cur1 into @id, @qry_out
    end
    close cur1
    deallocate cur1
  end

  if @step<=8 begin /* collect all FNs from source DB */
    set @qry='insert into dbp_level1 (obj_type, obj_id, obj_full_name, obj_schema, obj_name, obj_creation)
                select ''FN'', obj.object_id, ''[''+sch.name+''].[''+obj.name+'']'', sch.name, obj.name, txt.definition
                  from '+@src+'.sys.objects obj
                    join '+@src+'.sys.schemas sch on sch.schema_id=obj.schema_id
                    join '+@src+'.sys.sql_modules txt on txt.object_id=obj.object_id
                  where obj.type=''FN''
                  order by obj.name'
    exec (@qry)
  end

  if @step<=8 begin /* loop for FNs */
    declare cur1 cursor local static forward_only for select id, obj_creation from dbp_level1 where obj_type='FN' order by id
    open cur1
    fetch next from cur1 into @id, @qry_out
    while @@FETCH_STATUS=0 begin
      /* create default */
      exec (@qry_out)
      update dbp_level1 set obj_success=obj_success+1 where id=@id
      
      fetch next from cur1 into @id, @qry_out
    end
    close cur1
    deallocate cur1
  end

  if @step<=9 begin /* collect all views from source DB */
    set @qry='insert into dbp_level1 (obj_type, obj_id, obj_full_name, obj_schema, obj_name, obj_creation)
                select ''VW'', obj.object_id, ''[''+sch.name+''].[''+obj.name+'']'', sch.name, obj.name, txt.definition
                  from '+@src+'.sys.objects obj
                    join '+@src+'.sys.schemas sch on sch.schema_id=obj.schema_id
                    join '+@src+'.sys.sql_modules txt on txt.object_id=obj.object_id
                  where obj.type=''V''
                  order by obj.name'
    exec (@qry)
  end

  declare @errors int = 0, @passess int = 0

  if @step<=9 begin /* loop for views */
    while @passess<5 begin
      declare cur1 cursor local static forward_only for select id, obj_creation from dbp_level1 where obj_type='VW' and obj_success=0 order by id
      open cur1
      fetch next from cur1 into @id, @qry_out
      while @@FETCH_STATUS=0 begin
        /* create default */
        begin try
          exec (@qry_out)
          update dbp_level1 set obj_success=obj_success+1 where id=@id
        end try
        begin catch
          set @errors=1
        end catch
        fetch next from cur1 into @id, @qry_out
      end
      close cur1
      deallocate cur1
      set @passess=@passess+1
      if @errors=0
        break
    end
  end

  drop table dbp_level1;


