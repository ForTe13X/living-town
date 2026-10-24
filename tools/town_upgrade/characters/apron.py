"""A smooth, low-frequency apron guide with shared hip/knee drape controls.

The visible cloth is a ruled guide, not a copy of garment vertices. Native
outfit triangles constrain clearance, while conservative Gaussian padding
spreads every correction into broad curvature. Pocket and hem remain tidy.
"""
import math
from .skinning import ProjectedSurface,deform_points,pose_transforms,surface_envelope_report
from .seating import metrics_from_joints,solve as solve_seating


def lerp_profile(z,rows):
    if z<=rows[0][0]:return rows[0][1]
    for (a,x),(b,y) in zip(rows,rows[1:]):
        if z<=b:return x+(y-x)*(z-a)/(b-a)
    return rows[-1][1]


def smoothstep(value):
    value=max(0.,min(1.,value));return value*value*(3-2*value)


class ApronPattern:
    SIGMA=.070
    SOFTMAX=.0008

    def __init__(self,garment):
        self.garment=garment;self.fit_report={'enabled':False};self.hem_z=.465;self.columns=32
        self.rows=[.375+i*(1.291-.375)/76 for i in range(77)]
        self.guide_z=[.375+i*(1.291-.375)/36 for i in range(37)]
        self.padding_z=[.375+i*(1.04-.375)/50 for i in range(51)]
        self.padding=[0.]*len(self.padding_z);self._pocket_fit=None;self._padding_cache=None;self.clearance_margin=0.;self.upper_lift=0.;self.seat_kinematics=None;self.stature_scale=1.;self.seat_height_m=.462
        core={i for i,row in enumerate(garment['weights']) if sum(v for k,v in row.items() if k.startswith(('UpperArm','Forearm','Hand')))<.2}
        faces=[face for face in garment['faces'] if all(i in core for i,t in face)]
        surface=ProjectedSurface(garment['positions'],faces)
        raw=[]
        for z in self.guide_z:
            depths=[]
            for u in [-.85,-.6,-.3,0.,.3,.6,.85]:
                depth,_=surface.depth_at((u*self.width(z),0,z))
                if depth is not None:depths.append(depth+.006*u*u)
            raw.append(max(depths,default=.115))
        # A continuous Gaussian guide removes zipper, pocket and jean fold
        # imprints. Only its broad body silhouette remains under the apron.
        self.guide_y=[]
        for z in self.guide_z:
            weights=[math.exp(-.5*((height-z)/self.SIGMA)**2) for height in self.guide_z]
            self.guide_y.append(sum(value*w for value,w in zip(raw,weights))/sum(weights)+.008)
        self.profile=[(z,self.center(z)) for z in self.rows]

    def width(self,z):
        rows=[(.375,.145),(.455,.165),(.72,.168),(.974,.137),(1.04,.109),(1.291,.092)]
        if z<=rows[0][0]:return rows[0][1]
        for (a,x),(b,y) in zip(rows,rows[1:]):
            if z<=b:return x+(y-x)*smoothstep((z-a)/(b-a))
        return rows[-1][1]

    def base_center(self,z):
        weights=[math.exp(-.5*((height-z)/self.SIGMA)**2) for height in self.guide_z]
        return sum(value*w for value,w in zip(self.guide_y,weights))/sum(weights)

    def padding_at(self,z):
        # Gaussian-filter the soft support envelope as well: soft-max alone
        # can retain a visible horizontal ridge where two broad supports meet.
        if self._padding_cache is None:
            if not any(self.padding):return 0.
            step=.0025;origin=.30;count=441;raw=[]
            for i in range(count):
                height=origin+i*step
                values=[amount*math.exp(-.5*((center-height)/self.SIGMA)**2) for center,amount in zip(self.padding_z,self.padding) if amount>1e-8]
                peak=max(values,default=0.);tau=self.SOFTMAX
                raw.append(peak+tau*math.log(sum(math.exp((value-peak)/tau) for value in values)+math.exp(-peak/tau)))
            kernel=[(offset,math.exp(-.5*(offset*step/.022)**2)) for offset in range(-27,28)]
            smooth=[]
            for i in range(count):
                weights=[(max(0,min(count-1,i+offset)),weight) for offset,weight in kernel]
                smooth.append(sum(raw[j]*weight for j,weight in weights)/sum(weight for j,weight in weights))
            self._padding_cache=(origin,step,smooth)
        origin,step,values=self._padding_cache;t=max(0.,min(len(values)-1.,(z-origin)/step));index=int(t);fraction=t-index
        p0=values[max(0,index-1)];p1=values[index];p2=values[min(len(values)-1,index+1)];p3=values[min(len(values)-1,index+2)]
        return max(0.,.5*((2*p1)+(-p0+p2)*fraction+(2*p0-5*p1+4*p2-p3)*fraction**2+(-p0+3*p1-3*p2+p3)*fraction**3))

    def center(self,z):return self.base_center(z)+self.padding_at(z)

    @staticmethod
    def upper_profile(z):
        # One broad, symmetric fabric envelope spans both chest peaks. It
        # cannot copy a breast, shirt print, individual vertex or X column.
        # The compact transition leaves all accepted lower drape unchanged.
        return smoothstep((z-1.00)/.075)*math.exp(-.5*((z-1.215)/.075)**2)*smoothstep((1.275-z)/.100)

    def front(self,x,z):
        u=max(-1.,min(1.,x/self.width(z)))
        hang=smoothstep((self.hem_z+.065-z)/.13)
        center=self.center(z)*(1-hang)+self.center(self.hem_z)*hang
        lower=smoothstep((1.01-z)/.38)
        curvature=.006+.003*lower
        folds=.0018*lower*(.7*math.cos(math.pi*1.4*u)+.3*math.cos(math.pi*2.6*u))
        return center-curvature*u*u+folds+self.clearance_margin+self.upper_lift*self.upper_profile(z)

    def joints(self,pelvis,knee=None,*,fit=True,seat_kinematics=None,stature_scale=1.,seat_height_m=.462):
        body_joints=pelvis if isinstance(pelvis,dict) else None
        if body_joints is not None:
            knee=body_joints.get('Shin_L');pelvis=body_joints['PelvisRoot']
            self.seat_kinematics=seat_kinematics or metrics_from_joints(body_joints,0.)
        self.stature_scale=float(stature_scale);self.seat_height_m=float(seat_height_m)
        workwear_raise=.034 if self.garment['name']=='male_worksuit01' else 0.
        self.hem_z=(knee[2] if knee is not None else .465)+workwear_raise
        result={'ApronDrape':(pelvis[0],pelvis[1]+.034,pelvis[2]+.019+workwear_raise),
                'ApronHem':(0.,self.front(0,self.hem_z),self.hem_z)}
        if body_joints is not None and fit:self.fit_pose_envelope({**body_joints,**result})
        else:self.fit_report={'enabled':False,'reason':'no full rest rig or apron fitting not requested'}
        self._pocket_fit=None
        return result

    def weights(self,x,z):
        if z>=1.04:return {'BodyPivot':1.}
        if z>=.995:
            w=smoothstep((z-.995)/.045);return {'BodyPivot':w,'PelvisRoot':1-w}
        drape=smoothstep((.995-z)/.07)
        hem=smoothstep((self.hem_z+.075-z)/.15)
        return {'ApronDrape':drape*(1-hem),'ApronHem':drape*hem,'PelvisRoot':1-drape}

    def surface(self):
        vertices=[];faces=[];uv=[];weights=[]
        for row,z in enumerate(self.rows):
            for col in range(self.columns+1):
                u=col/self.columns*2-1;x=u*self.width(z)
                # Rounded lower corners shorten the heavy rectangular hem.
                rounded=.014*(abs(u)**4)*(1-smoothstep((z-.375)/.10))
                vertices.append((x,self.front(x,z),z+rounded));uv.append((x*4,z*4));weights.append(self.weights(x,z))
                if row and col:
                    i=row*(self.columns+1)+col;faces.append((i-self.columns-2,i-1,i,i-self.columns-1))
        return thicken((vertices,faces,uv),weights)

    def pocket_front(self,x,z):
        if self._pocket_fit is None:
            bottom=self.front(0,.805);middle=self.front(0,.855);top=self.front(0,.905)
            a=middle;b=(top-bottom)/.10;c=(top+bottom-2*middle)/(.005)
            def patch(x,z):return a+b*(z-.855)+c*(z-.855)**2-.007*(x/self.width(z))**2
            raise_by=max(self.front(x,z)-patch(x,z) for z in [.805+i*.01 for i in range(11)] for x in [-.064+i*.0128 for i in range(11)])+.0020
            self._pocket_fit=(a,b,c,raise_by)
        a,b,c,raise_by=self._pocket_fit;t=max(0,min(1,(z-.805)/.1))
        return a+b*(z-.855)+c*(z-.855)**2-.007*(x/self.width(z))**2+raise_by+.0010*4*t*(1-t)*max(0,1-(x/.065)**2)

    def pocket(self):
        vertices=[];faces=[];uv=[];weights=[];n=12
        for row in range(n+1):
            z=.805+.10*row/n
            for col in range(n+1):
                x=-.064+.128*col/n
                vertices.append((x,self.pocket_front(x,z),z));uv.append((x*4,z*4));weights.append(self.weights(x,z))
                if row and col:
                    i=row*(n+1)+col;faces.append((i-n-2,i-1,i,i-n-1))
        return thicken((vertices,faces,uv),weights,thickness=.001)

    def fit_pose_envelope(self,joints):
        self.padding=[0.]*len(self.padding_z);self._padding_cache=None;self.clearance_margin=0.;self.upper_lift=0.
        faces=[face for face in self.garment['faces'] if all(self.garment['unposed'][i][2]<.97 for i,t in face)]
        native=solve_seating(self.seat_kinematics,self.seat_height_m,self.stature_scale,0.)
        runtime=solve_seating(self.seat_kinematics,self.seat_height_m,self.stature_scale,.025)
        cases=[('Sit',.25),('Sit_runtime',.25),('Soak',.25),('Walk',.125),('Walk',.25),('Walk',.625),('Walk',.75)]
        def parameters(case):
            label,phase=case;clip='Sit' if label.startswith('Sit') else label
            solution=native if label=='Sit' else runtime if label=='Sit_runtime' else None
            poses=solution['poses'] if solution else {'ApronHem':(-math.pi/2,0.,0.)} if clip=='Soak' else {'ApronHem':(0.,0.,0.)}
            pelvis_z=solution['source_pelvis_height_m'] if solution else (.36+.025)/self.stature_scale if clip=='Soak' else None
            return clip,phase,poses,pelvis_z
        baseline_geometry,baseline_weights=self.surface();inner={};transforms={};surfaces={};baseline={}
        for case in cases:
            clip,phase,poses,pelvis_z=parameters(case)
            source=self.garment.get('seat_contact_target',self.garment['positions']) if clip in ('Sit','Soak') else self.garment['positions']
            inner[case]=deform_points(source,self.garment['weights'],joints,clip=clip,phase=phase,poses=poses,pelvis_z=pelvis_z)
            transforms[case]=pose_transforms(joints,clip=clip,phase=phase,poses=poses,pelvis_z=pelvis_z)
            surfaces[case]={axis:ProjectedSurface(inner[case],faces,axis) for axis in ([1,2] if clip in ('Sit','Soak') else [1])}
            baseline[case]=deform_points(baseline_geometry[0],baseline_weights,joints,clip=clip,phase=phase,poses=poses,pelvis_z=pelvis_z)
        adjustments=0
        for iteration in range(5):
            extra=[0.]*len(self.padding_z)
            for case in cases:
                clip,phase,poses,pelvis_z=parameters(case)
                points=[];weights=[];indices=[]
                for row,z in enumerate(self.padding_z):
                    if z>.98:continue
                    for u in [-.92,-.75,-.5,-.25,0.,.25,.5,.75,.92]:
                        x=u*self.width(z);points.append((x,self.front(x,z),z));weights.append(self.weights(x,z));indices.append(row)
                posed=deform_points(points,weights,joints,clip=clip,phase=phase,poses=poses,pelvis_z=pelvis_z)
                for point,row_weights,row in zip(posed,weights,indices):
                    corrections=[];clear=False
                    for axis,surface in surfaces[case].items():
                        depth,_=surface.depth_at(point)
                        if depth is None:continue
                        need=(.014 if clip in ('Sit','Soak') else .016)-(point[axis]-depth)
                        if need<=0:clear=True;break
                        sensitivity=sum(weight*transforms[case][name]['rotation'][axis][1] for name,weight in row_weights.items())
                        if sensitivity>.3:corrections.append(need/sensitivity)
                    if not clear and corrections:
                        extra[row]=max(extra[row],min(corrections));adjustments+=1
            for row,required in enumerate(extra):
                limit=.066 if self.garment['name']=='male_worksuit01' else .060
                if required>0:self.padding[row]=min(limit,self.padding[row]+min(.020,required))
            self._padding_cache=None
            if max(extra,default=0)<.0003:break
        self._pocket_fit=None
        # Applied after constrained fitting, so the solver cannot consume the
        # safety allowance. It shifts the same smooth guide by only1.5mm.
        self.clearance_margin=.0015
        self.profile=[(z,self.center(z)) for z in self.rows]
        reports={};geometry,weights=self.surface();vertices,outer_faces,_=geometry
        chosen=[face for face in outer_faces if all(vertices[i][2]<.97 for i in face)]
        selected=sorted({i for face in chosen for i in face});remap={index:i for i,index in enumerate(selected)}
        filtered=[tuple(remap[i] for i in face) for face in chosen]
        for case in cases:
            clip,phase,poses,pelvis_z=parameters(case)
            outer=deform_points(vertices,weights,joints,clip=clip,phase=phase,poses=poses,pelvis_z=pelvis_z)
            report=surface_envelope_report([outer[i] for i in selected],inner[case],faces,outer_faces=filtered,axes=(1,2) if clip in ('Sit','Soak') else (1,),minimum_clearance=.005,max_examples=8)
            delta=[math.dist(point,baseline[case][i]) for i,point in enumerate(outer)]
            report.update(maximum_profile_displacement_m=max(delta),mean_profile_displacement_m=sum(delta)/len(delta))
            reports[case[0]+'_'+str(phase)]=report
        self.fit_report={'enabled':True,'method':'one smooth ruled center guide, quadratic cross-section and conservative Gaussian clearance envelope',
            'gaussian_sigma_m':self.SIGMA,'softmax_m':self.SOFTMAX,'post_fit_clearance_margin_m':self.clearance_margin,'independent_cross_section_columns':0,
            'maximum_added_padding_m':max(self.padding_at(z) for z in self.rows),'mean_added_padding_m':sum(self.padding_at(z) for z in self.rows)/len(self.rows),
            'adjusted_samples':adjustments,'iterations':iteration+1,'cases':reports,'units':'normalized 1.665m source; multiply by persona stature ratio',
            'source_clearance_validation_required':True,'seating_solutions':{'Sit':native,'Sit_runtime':runtime},'seat_contact_target_used':bool(self.garment.get('seat_contact_target')),
            'soak_policy':'Retains90degree bath pose; native root0 pelvis=(.36+.025)/statureScale matches runtime root25mm world height'}
        self.fit_upper_guide(joints)

    def fit_upper_guide(self,joints):
        """Fit one smooth upper-bib amplitude against actual posed shirts.

        The inside lining, including linear triangle interiors, constrains a
        single broad source-Y profile. Topology, X/Z, UVs, weights and the
        accepted lower surface are invariant; no underlying faces are hidden.
        """
        from .assets import geometry_for
        from .animation import pose_values,pelvis_height
        self.upper_lift=0.;target=.0025;cap=.032
        shirt_ids=set(geometry_for(self.garment,'shirt')[2])
        core={i for i in shirt_ids if 1.005<self.garment['unposed'][i][2]<1.34 and sum(v for k,v in self.garment['weights'][i].items() if k.startswith(('UpperArm','Forearm','Hand')))<.2}
        shirt_faces=[face for face in self.garment['faces'] if all(i in core for i,t in face)]
        geometry,_=self.surface();vertices,faces,_=geometry;n=len(vertices)//2
        chosen=[face for face in faces if max(face)<n and all(vertices[i][2]>=1.04-1e-9 for i in face)]
        selected=sorted({i for face in chosen for i in face})
        samples=[vertices[n+i] for i in selected];gains=[self.upper_profile(vertices[i][2]) for i in selected]
        for face in chosen:
            for fan in range(1,len(face)-1):
                triangle=(face[0],face[fan],face[fan+1]);points=[vertices[n+i] for i in triangle];basis=[self.upper_profile(vertices[i][2]) for i in triangle]
                for bary in [(1/3,1/3,1/3),(.25,.25,.5),(.25,.5,.25),(.5,.25,.25)]:
                    samples.append(tuple(sum(p[k]*weight for p,weight in zip(points,bary)) for k in range(3)))
                    gains.append(sum(value*weight for value,weight in zip(basis,bary)))
        cases=[(None,0.),('Idle',.25),('Walk',.125),('Walk',.375),('Walk',.625),('Walk',.875),('Sit',.25),('Lie',.25),('Work',.25),('Talk',.25),('Soak',.25)]
        states=[]
        for clip,phase in cases:
            poses=pose_values(clip,phase,seat_metrics=self.seat_kinematics,stature_scale=self.stature_scale) if clip else None
            pelvis=pelvis_height(clip,phase,joints['PelvisRoot'][2],1.,seat_metrics=self.seat_kinematics,stature_scale=self.stature_scale) if clip else None
            source=self.garment.get('seat_contact_target',self.garment['positions']) if clip in ('Sit','Soak') else self.garment['positions']
            inner=deform_points(source,self.garment['weights'],joints,clip=clip,phase=phase,poses=poses,pelvis_z=pelvis,scale=self.stature_scale)
            outer=deform_points(samples,[{'BodyPivot':1.}]*len(samples),joints,clip=clip,phase=phase,poses=poses,pelvis_z=pelvis,scale=self.stature_scale)
            rotation=pose_transforms(joints,clip=clip,phase=phase,poses=poses,pelvis_z=pelvis)['BodyPivot']['rotation']
            direction=tuple(rotation[k][1]*self.stature_scale for k in range(3));axis=2 if clip=='Lie' else 1
            states.append({'key':(clip or 'Rest')+'_'+str(phase),'outer':outer,'direction':direction,'axis':axis,'surface':ProjectedSurface(inner,shirt_faces,axis)})
        def measure(state):
            gaps=[];required=self.upper_lift
            for point,basis in zip(state['outer'],gains):
                posed=tuple(point[k]+state['direction'][k]*basis*self.upper_lift for k in range(3));depth,_=state['surface'].depth_at(posed)
                if depth is None:continue
                gap=posed[state['axis']]-depth;gaps.append(gap);sensitivity=state['direction'][state['axis']]*basis
                if gap<target and sensitivity>1e-7:required=max(required,self.upper_lift+(target-gap+.00005)/sensitivity)
            return {'matched_samples':len(gaps),'sample_count':len(samples),'minimum_world_lining_clearance_m':min(gaps) if gaps else None,'violation_samples':sum(value<.002-1e-9 for value in gaps)},required
        before={state['key']:measure(state)[0] for state in states}
        for iteration in range(4):
            required=max(measure(state)[1] for state in states)
            if required-self.upper_lift<1e-7:break
            self.upper_lift=min(cap,required)
        after={state['key']:measure(state)[0] for state in states}
        self.fit_report['upper_bib']={'enabled':True,'method':'one X-independent broad Gaussian fabric profile, constrained by emitted lining vertices and triangle interiors against actual posed torso shirt triangles',
            'profile_center_source_m':1.215,'profile_sigma_source_m':.075,'lower_invariant_at_or_below_source_z_m':1.00,'lower_transition_width_source_m':.075,'upper_invariant_at_or_above_source_z_m':1.275,'upper_transition_width_source_m':.100,
            'maximum_amplitude_source_m':self.upper_lift,'maximum_allowed_amplitude_source_m':cap,'target_world_lining_clearance_m':target,
            'stature_scale':self.stature_scale,'independent_columns':0,'topology_uv_xz_weights_preserved':True,'iterations':iteration+1,
            'before':before,'after':after,'success':all(row['matched_samples'] and not row['violation_samples'] for row in after.values()),
            'limitation':'Finite sampled directional surface clearance; native visual review remains required.'}


def thicken(geometry,weights,thickness=.0016):
    vertices,faces,uv=geometry;n=len(vertices);edges={}
    for face in faces:
        for a,b in zip(face,face[1:]+face[:1]):
            key=tuple(sorted((a,b)));edges.setdefault(key,[]).append((a,b))
    result_faces=list(faces)+[tuple(i+n for i in reversed(face)) for face in faces]
    for rows in edges.values():
        if len(rows)==1:
            a,b=rows[0];result_faces.append((a,a+n,b+n,b))
    return (vertices+[(x,y-thickness,z) for x,y,z in vertices],result_faces,uv+uv),weights+weights
