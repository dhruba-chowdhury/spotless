classdef spotprog
%  TODO:
%
%  -- Every spot_decomp_linear should come with a potential error stmt.
%
%  -- Move /all/ variables with the same name so that cstr issued
%  variables can be renamed.
%
%
    properties 
        %
        % Basic Representation:
        %
        % Primal:
        %
        %    min (c1,f)+(c2,x), 
        %    x in K1,  
        %    A1*f+A2*x = b, 
        %    g - F1*f-F2*x = r in K2.
        %
        % Dual:
        %  
        %    max. (y,b) - (q,g),
        %    q in K2*,
        %    c-A2'y-F2'*q = z in K1*,
        %    c1 = A1'*y+F1'*q
        %
        % variables = x(p).
        %
        K1 = struct('f',0,'l',0,'q',[],'r',[],'s',[]);
        K2 = struct('f',0,'l',0,'q',[],'r',[],'s',[]);
        
        % w = [x;z],  w(p(i)) corresponds to variable i.
        % Really, I want v(p(i)) corresponds to variable x(i).
        %
        
        coneVar = [];
        coneToVar = [];
        
        coneCstrVar = [];
        dualCstrVar = [];
        coneToCstrVar = [];
        
        A = [];
        b = [];
        
        g = [];
        F = [];
        
        name = '@';
        varIndices = [];
    end
    
    methods (Static)
        function n = psdDimToNo(d)
            n=(d+1).*d/2;
        end
        function [d,err] = psdNoToDim(n)
            d=round((sqrt(1+8*n)-1)/2);
            if spotprog.psdDimToNo(d) ~= n
                d = NaN;
                err = 1;
            else
                err = 0;
            end
        end
        
        function flag = isScalarDimension(n)
            flag = spot_hasSize(n,[1 1]) && ...
                   spot_isIntGE(n,0);
        end
        function flag = isVectorDimension(n)
            flag = size(n,1) == 1 && spot_isIntGE(n,0);
        end
        function dim = checkCstrDimension(e,dim)
            if ~spotprog.isVectorDimension(dim)
                error('dim must be a vector of non-negative scalars.');
            end
            if size(e,2) ~= 1
                dim = repmat(dim,1,size(e,2));
                e = e(:);
            end
            if sum(dim) ~= length(e)
                error('Dimension and vector size disagree.');
            end
        end
        function [nf,nl,nq,nr,ns] = coneDim(K)
            nf = K.f;
            nl = K.l;
            nq = sum(K.q);
            nr = sum(K.r);
            ns = sum(spotprog.psdDimToNo(K.s));
        end
        
        function [of,ol,oq,or,os] = coneOffset(K)
            of = K.f;
            ol = of+K.l;
            oq = ol+sum(K.q);
            or = oq+sum(K.r);
            os = or+sum(spotprog.psdDimToNo(K.s));
        end
    end
    
    methods ( Access = private )        
        function n = numVar(pr)
            n = length(pr.coneVar) + length(pr.coneCstrVar) + ...
                length(pr.dualVar) + length(pr.dualCstrVar);
        end


        function n = numEquations(pr)
            n = size(pr.A,1);
        end
        
        

        
        function nm = varName(prog)
            nm = [prog.name 'var'];
        end
        
        
        function off = freeOffset(pr)
            off = spotprog.coneOffset(pr.K1);
        end
        
        function off = posOffset(pr)
            [~,off] = spotprog.coneOffset(pr.K1);
        end
        
        function off = lorOffset(pr)
            [~,~,off] = spotprog.coneOffset(pr.K1);
        end
        
        function off = rlorOffset(pr)
            [~,~,~,off] = spotprog.coneOffset(pr.K1);
        end
        
        function off = psdOffset(pr)
            [~,~,~,~,off] = spotprog.coneOffset(pr.K1);
        end
        
        function off = posCstrOffset(pr)
            [~,off] = spotprog.coneOffset(pr.K2);
        end
        
        function off = lorCstrOffset(pr)
            [~,~,off] = spotprog.coneOffset(pr.K2);
        end
        
        function off = rlorCstrOffset(pr)
            [~,~,~,off] = spotprog.coneOffset(pr.K2);
        end
        
        function off = psdCstrOffset(pr)
            [~,~,~,~,off] = spotprog.coneOffset(pr.K2);
        end
        
                
        function [pr,v] = insertVariables(pr,offset,number)
            pr.A = [ pr.A(:,1:offset) ...
                     sparse(size(pr.A,1),number) ...
                     pr.A(:,offset+1:end) ];
            
            pr.F = [ pr.F(:,1:offset) ...
                     sparse(size(pr.F,1),number) ...
                     pr.F(:,offset+1:end) ];
            
            v = msspoly(pr.varName,[number pr.numVar]);            
            
            pr.coneVar = [ pr.coneVar ; v];
            shift = pr.coneToVar > offset;
            pr.coneToVar(shift) = pr.coneToVar(shift) + number;
            pr.coneToVar = [ pr.coneToVar ; offset+(1:number)'];
        end
        
        function pr = insertConstraints(pr,offset,Fnew,gnew)
            pr.F = [ pr.F(1:offset,:)
                     Fnew
                     pr.F(offset+1:end,:)];
            pr.g = [ pr.g(1:offset,:)
                     gnew
                     pr.g(offset+1:end,:)];
        end
        
        function [pr,z,y] = addConstraintExpr(pr,off,e)
            [Fnew,gnew] = spot_decomp_linear(-e(:),pr.variables);
            [~,I] = sort(pr.coneToVar);
            pr = pr.insertConstraints(off,Fnew(:,I),gnew);
            
            n = size(Fnew,1);

            z = msspoly(pr.varName,[n pr.numVar]);
            y = msspoly(pr.varName,[n pr.numVar+length(z)]);
            
            pr.dualCstrVar = [ pr.dualCstrVar(1:off) 
                               y 
                               pr.dualCstrVar(off+1:length(pr.dualCstrVar))];
            
            pr.coneCstrVar = [pr.coneCstrVar ; z];
            shift = pr.coneToCstrVar > off;
            pr.coneToCstrVar(shift) = pr.coneToCstrVar(shift) + n;
            pr.coneToCstrVar = [ pr.coneToCstrVar ; off+(1:n)' ];
        end
    end

    methods
        function pr = spotprog()
        end
        
        function v = variables(pr)
            v = pr.coneVar;
        end
        
        function v = cstrVariables(pr)
            v = pr.coneCstrVar;
        end
        
        function nf = numFree(pr)
            nf = pr.coneDim(pr.K1);
        end
        
        function v = decToVar(prog,x)
            v = x(prog.coneToVar);
            % [~,I] = sort(prog.coneToVar);
            % v = x(I);
        end
        
        function y = dualEqVariables(pr)
            y = msspoly(pr.eqDualName,pr.numEquations);
        end
        
        function [pr,y] = withEqs(pr,e)
            e = e(:);
            y = msspoly(pr.varName,[length(e) pr.numVar]);
            pr.dualVar = [ pr.dualVar ; y];
            [Anew,bnew] = spot_decomp_linear(e,pr.variables);
            [~,I] = sort(pr.coneToVar);
            pr.b = [ pr.b ; bnew];
            pr.A = [ pr.A ; Anew(:,I) ];

        end
        
        function [pr,z,y] = withCone(pr,e,K)
            [nf,nl,nq,nr,ns]=spotprog.coneDim(K);
            [of,ol,oq,or,os]=spotprog.coneOffset(K);
            if nf+nl+nq+nr+ns ~= size(e,1)
                error('Cone size does not match dim.');
            end

            if size(e,2) == 0, return; end
            
            if nl > 0, [pr,zl,yl] = pr.withPos(e(1:of));
            else, zl = []; yl = []; end

            if nq > 0, [pr,zq,yq] = pr.withLor(e(of+(1:oq)),K.q);
            else, zq = []; yq = []; end

            if nr > 0, [pr,zr,yr] = pr.withRLor(e(oq+(1:or)),K.r);
            else, zr = []; yr = []; end

            if ns > 0, [pr,zs,ys] = pr.withBlkPSD(e(or+(1:os)),K.s);
            else, zs = []; ys = []; end
            
            y = [ yl ; yq ; yr ; ys ];
            z = [ zl ; zq ; zr ; zs ];
            
        end
        
        
        function [pr,z,y] = withPos(pr,e)
            n = prod(size(e));
            off = pr.posCstrOffset;
            pr.K2.l = pr.K2.l + n;
            
            [pr,z,y] = addConstraintExpr(pr,off,e);
        end
        
        function [pr,z,y] = withLor(pr,e,dim)
            if nargin < 3,
                dim = size(e,1);
            end
            
            dim = spotprog.checkCstrDimension(e,dim);

            off = pr.lorCstrOffset;
            pr.K2.q = [pr.K2.q dim];
            
            [pr,z,y] = addConstraintExpr(pr,off,e);
        end
       
        function [pr,z,y] = withRLor(pr,e,dim)
            if nargin < 3,
                dim = size(e,1);
            end
            
            dim = spotprog.checkCstrDimension(e,dim);
            
            off = pr.rlorCstrOffset;
            pr.K2.r = [pr.K2.r dim];
            
            [pr,z,y] = addConstraintExpr(pr,off,e);
        end
        
        function [pr,z,y] = withBlkPSD(pr,e,dim)
            if nargin < 3,
                [dim,v] = spotprog.psdNoToDim(size(e,1));
                if v,
                    error(['expression size incorrect (not upper ' ...
                           'triangular of symmetric matrix).']);
                end
            end
            
            if ~spot_isIntGE(dim,0),
                error('dim must be non-negative integer.');
            end

            no = spotprog.psdDimToNo(dim);
            
            no = spotprog.checkCstrDimension(e,no);

            off = pr.psdCstrOffset;
            pr.K2.s = [pr.K2.s spotprog.psdNoToDim(no)];
            
            [pr,z,y] = pr.addConstraintExpr(off,e);
        end
        
        function [pr,z,y] = withPSD(pr,e)
            if size(e,1) ~= size(e,2)
                error('Arugment must be square.');
            end
            [pr,z,y] = pr.withBlkPSD(mss_s2v(e));
            z = mss_v2s(z);
        end
        
        function [pr,v] = newFree(pr,n,m)
            if nargin < 3, m = 1; end
            if ~spotprog.isScalarDimension(n)
                error('n must be a non-negative integer scalar.');
            end
            if ~spotprog.isScalarDimension(m)
                error('m must be a non-negative integer scalar.');
            end
            nf = pr.freeOffset;
            pr.K1.f = pr.K1.f + n*m;
            [pr,v] = pr.insertVariables(nf,n*m);
            v = reshape(v,n,m);
        end
        
        function [pr,v] = newPos(pr,n,m)
            if nargin < 3, m = 1; end
            if ~spotprog.isScalarDimension(n)
                error('n must be a non-negative integer scalar.');
            end
            if ~spotprog.isScalarDimension(m)
                error('m must be a non-negative integer scalar.');
            end
            nl = pr.posOffset;
            pr.K1.l = pr.K1.l + n*m;
            [pr,v] = pr.insertVariables(nl,n*m);
            v = reshape(v,n,m);
        end

        function [pr,v] = newLor(pr,dim,m)
            if nargin < 3, m = 1; end
            if ~spotprog.isVectorDimension(dim)
                error('dim must be a row of non-negative scalars.');
            end
            if ~spotprog.isScalarDimension(m)
                error('m must be a non-negative integer scalar.');
            end
            nq = pr.lorOffset;
            n = sum(dim);
            [pr,v] = pr.insertVariables(nq,n*m);
            pr.K1.q = [ pr.K1.q repmat(dim,1,m) ];
            v = reshape(v,n,m);
        end
        
        function [pr,v] = newRLor(pr,dim,m)
            if nargin < 3, m = 1; end
            if ~spotprog.isVectorDimension(dim)
                error('dim must be a row of non-negative scalars.');
            end
            if ~spotprog.isScalarDimension(m)
                error('m must be a non-negative integer scalar.');
            end
            nr = pr.rlorOffset;
            n = sum(dim);
            [pr,v] = pr.insertVariables(nr,n*m);
            pr.K1.r = [ pr.K1.r repmat(dim,1,m) ];
            v = reshape(v,n,m);
        end
        
        function [pr,v] = newBlkPSD(pr,dim,m)
            if nargin < 3, m = 1; end
            if ~spotprog.isVectorDimension(dim)
                error('dim must be a row of non-negative scalars.');
            end
            if ~spotprog.isScalarDimension(m)
                error('m must be a non-negative integer scalar.');
            end
            ns = pr.psdOffset;
            d = spotprog.psdDimToNo(dim);
            n = sum(d);
            [pr,v] = pr.insertVariables(ns,n*m);
            pr.K1.s = [ pr.K1.s repmat(dim,1,m) ];
            v = reshape(v,n,m);
        end
        
        function [pr,V] = newPSD(pr,dim)
            if ~spotprog.isScalarDimension(dim)
                error('dim must be a row of non-negative scalars.');
            end
            [pr,v] = pr.newBlkPSD(dim);
            V = mss_v2s(v);
        end
        
        function pred = isStandardDual(pr)
            pred = pr.numEquations == 0 && spotprog.coneDim(pr.K1) == 0;
        end
        
        function pred = isPrimalWithFree(pr)
            pred = 0 == pr.K2.l && ...
                   isempty([ pr.K2.q pr.K2.r pr.K2.s]);
        end
        
        
        
        
        function [sol] = minimize(prog,pobj,solver)
            if nargin < 2,
                pobj = 0;
            end
            if nargin < 3,
                solver = @spot_sedumi;
            end
            
            pobj = msspoly(pobj);

            pr = prog.primalize();
            [nf] = spotprog.coneDim(pr.K1);
            [P,A,b,c,K,d] = pr.toSedumi(pobj);
            
            % Enable removal of redundant equations.
            [feas,E,F,g,U,V,w,Ad,bd,cd,Kd] = spot_sdp_remove_redundant_eqs(A,b,c,K);

            % Enable basic facial reduction.
            [x,y,z,info] = solver(Ad,bd,cd,Kd);

            x = E\(F*x+g);
            y = U\(V*y+w);
            z = c - A'*y;

            xsol = P*x;
            zsol = P(nf+1:end,nf+1:end)*z(nf+1:end);

            sol = spotprogsol(pr,pobj,xsol,y,zsol,info);
        end
    end
    
    methods (Access = public)
        function [P,A,b,c,K,d] = toSedumi(pr,pobj)
            if ~pr.isPrimalWithFree()
                error(['Problem must be primal with free variables, ' ...
                       ' see toPrimalWithFree().']);
            end
            if ~spot_hasSize(pobj,[1 1])
                error('Objective must be scalar.');
            end
            
            [c,nd] = spot_decomp_linear(pobj,pr.variables);
            d = -nd;
            
            [~,I] = sort(pr.coneToVar);
            c = c(I)';
            
            projMap = containers.Map('KeyType','uint32','ValueType','any');
            ssize = unique(pr.K1.s);
            for i = 1:length(ssize)
                n = ssize(i);
                I = mss_s2v(reshape(1:n^2,n,n));
                projMap(ssize(i)) = sparse((1:length(I))',I,ones(size(I)),length(I),n^2);
            end
            
            [nf,nl,nq,nr,ns] = spotprog.coneDim(pr.K1);

            projs = cell(1,length(pr.K1.s));
            for i = 1:length(pr.K1.s)
                projs{i} = projMap(pr.K1.s(i));
            end
            if isempty(projs), P = [];
            else, P = blkdiag(projs{:});
            end
            A = [ pr.A(:,1:nf+nl+nq+nr) pr.A(:,nf+nl+nq+nr+(1:ns))*P];
            
            c = [ c(1:nf+nl+nq+nr)
                  P'*c((nf+nl+nq+nr)+(1:ns))];
            
            b = pr.b;
            P = blkdiag(speye(nf+nl+nq+nr),P);
            K = pr.K1;
        end
    end
end