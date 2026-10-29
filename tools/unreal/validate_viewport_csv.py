"""Validate dense native Game-viewport CSV evidence; no displayed-FPS inference."""
from pathlib import Path
import csv,hashlib,math

FIELDS=('LTViewportWidth','LTViewportHeight','LTViewportGTFrame','LTViewportSamples')
MAXIMUM_EXACT_FRAME=(1<<24)-1

def need(ok,message):
    if not ok:raise ValueError(message)

def qualify_rows(header,raw,boundary_row,expected=(1920,1080)):
    need(all(header.count(name)==1 for name in FIELDS),'Four unique native viewport CSV columns required')
    need(0<=boundary_row<len(raw)-1,'Observed retained boundary required')
    columns={name:header.index(name)for name in FIELDS}
    previous=None;first=None;count=0
    for row_index in range(boundary_row+1,len(raw)):
        row=raw[row_index];values={}
        for name,index in columns.items():
            need(index<len(row)and row[index]!='',f'Missing native viewport sample at CSV row {row_index}: {name}')
            try:value=float(row[index])
            except (ValueError,TypeError):raise ValueError(f'Non-numeric native viewport sample at CSV row {row_index}: {name}')
            need(math.isfinite(value)and value==math.trunc(value),f'Non-finite or fractional native viewport sample at CSV row {row_index}: {name}')
            values[name]=int(value)
        need(values['LTViewportSamples']==1,f'Expected one game-thread viewport sample at CSV row {row_index}; got {values["LTViewportSamples"]}')
        extent=(values['LTViewportWidth'],values['LTViewportHeight'])
        need(extent==tuple(expected),f'Native viewport extent changed at CSV row {row_index}: {extent}, required {tuple(expected)}')
        frame=values['LTViewportGTFrame']
        need(0<frame<=MAXIMUM_EXACT_FRAME,f'Unqualified native frame-counter range at CSV row {row_index}: {frame}')
        need(previous is None or frame==previous+1,f'Native game-thread frame counter is not consecutive at CSV row {row_index}: {previous} -> {frame}')
        if first is None:first=frame
        previous=frame;count+=1
    return {'status':'PASS_PER_RETAINED_ROW_NATIVE_GAME_VIEWPORT_EXTENT_AND_FRAME_SEQUENCE',
            'retained_rows':count,'expected_native_viewport_extent':list(expected),
            'first_GT_frame':first,'last_GT_frame':previous,'every_retained_CSV_row_checked':True,
            'native_field_names':list(FIELDS),'backbuffer_or_internal_view_rect_measured':False,
            'causal_performance_or_displayed_FPS_accepted':False}

def qualify_csv(path,expected=(1920,1080)):
    path=Path(path);need(path.is_file()and 0<path.stat().st_size<=512*1024**2,'Finite actual native CSV required')
    previous_limit=csv.field_size_limit();csv.field_size_limit(8*1024**2)
    try:
        with path.open(encoding='utf-8-sig',newline='')as f:rows=list(csv.reader(f))
    finally:csv.field_size_limit(previous_limit)
    headers=[i for i,row in enumerate(rows)if row and row[0]=='EVENTS']
    need(len(headers)==2 and headers[0]==0,'Actual first/final native EVENTS schema required')
    header=rows[headers[-1]];need(rows[0]==header[:len(rows[0])],'Native final schema reordered prior fields')
    raw=rows[1:headers[-1]];boundary=[i for i,row in enumerate(raw)if row and'CsvExecCommand : GetMaxTickRate'in row[0]]
    need(len(boundary)==1,'Unique observed native retained-boundary event required')
    result=qualify_rows(header,raw,boundary[0],expected)
    with path.open('rb')as f:digest=hashlib.file_digest(f,'sha256').hexdigest()
    result.update(raw_csv={'path':str(path.resolve()),'bytes':path.stat().st_size,'sha256':digest},boundary_CSV_row0=boundary[0])
    return result
