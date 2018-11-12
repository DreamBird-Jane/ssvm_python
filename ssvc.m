function [w, b] = ssvc(A, B, nu, w0, b0)
    %#####################################################################
    %# Smooth Support Vector Machine                                     #
    %# Authors: Yuh-Jye Lee and O. L. Mangasarian                        #
    %# Programers: Yuh-Jye Lee and Chien-Ming Huang                      #
    %# Web Site: http://dmlab1.csie.ntust.edu.tw/downloads/              #
    %# Date: 5/4/2005                                                    #
    %# Version: 0.03                                                     #
    %#                                                                   #
    %# This software is available for non-commercial use only.           #
    %# It must not be modified and distributed without prior             #
    %# permission of the authors.                                        #
    %# The authors are not responsible for implications from             #
    %# the use of this software.                                         #
    %#                                                                   #
    %# Please send comments and suggestions to                           #
    %# "yuh-jye@mail.ntust.edu.tw"                                       #
    %#                                                                   #
    %# Inputs                                                            #
    %#   A: Represent A+ data                                            #
    %#   B: Represent A- data                                            #
    %#   [w0; b0]: Initial point                                         #
    %#   nu: weight parameter                                            #
    %#                                                                   #
    %# Outputs                                                           #
    %#   w: the normal vector of the classifier                          #
    %#   b: the threshold                                                #
    %#                                                                   #
    %# Note:                                                             #
    %#   1. In order to handle a massive dataset this code               #
    %#      takes the advantage of sparsity of the Hessian               #
    %#      matrix.                                                      #
    %#                                                                   #
    %#   2. We used the limit values of the sigmoid function             #
    %#      and p-function as the smoothing parameter \alpha             #
    %#      goes to infinity when we compute the Hessian                 #
    %#      matrix and the gradient of objective function.               #
    %#                                                                   #
    %#   3. Decrease nu when the classifier is overfitting               #
    %#      the training data.                                           #
    %#                                                                   #
    %#   4. The form of classifier is w'x-b (x is a test point).         #
    %#                                                                   #
    %#####################################################################


    %C=[A;-B]; % equals "DA" in SSVM paper
    [ma, n] = size(A); mb = length(B(:,1));
    d = [ones(ma, 1); -ones(mb, 1)]; % equal "De" is the paper
    e = ones(ma+mb, 1); 


    if (nargin < 5 )
        % get initial point from RLS 
        % disp(['Using initial point from regularized least squares!'])
        AE = [[A;B] e];
        %X = (AE'*AE)\(AE'*y);

        %Solve "X = inv(AE'*AE + lamda*I)*(A'*d)" by Cholesky docomposition
        R = chol([[AE'*AE]+0.01*eye(n+1) AE'*d;d'*AE d'*d]);
        X = R(1:n+1,1:n+1)\R(1:n+1,n+2);

        w0 = X(1:n);
        b0 = -X(n+1);
    end


    flag = 1;
    while flag > 1E-4
      % Find a search direction!
      rv =  e - [(A*w0 -b0); (-(B*w0-b0))]; % e - D(Aw0 - e \b0)

      % Compute the Hessian matrix                
      H = (e + sign(rv))/2; % H(i) is the limit of sigmoid function, on SSVM p.13
      Ih = find(H ~= 0); % We only consider the nonzero part
      if(isempty(Ih))  % Sometime, the length of Ih will be zero. 
          break;         % In this condition, we can finish this job directly.
      end
      Hs = H(Ih);

      clear H; % Release memory  

      IC = [A(Ih(Ih<=ma), :); -B(Ih(Ih>ma)-ma, :)]; 
      SH = spdiags(Hs, 0, speye(length(Ih)))*IC;
      P = SH'*IC; q = SH'*d(Ih);

      clear IC SH Ih; % Release memory

      % Q is the Hessian matrix
      Q = (1/nu)*speye(n+1)+[P, (-q); (-q'), norm(Hs,1)];
      clear P q; % Release memory

      % Compute the gradient  
      prv = max(rv, 0); % (e- D(Aw0 - e \b0))_+
      prva= A'*prv(1:ma); prvb=-(B'*prv(ma+1:end));
      gradz = (1/nu)*[w0; b0]-[prva+prvb;-d'*prv];

      clear rv prv prva prvb; % Release memory

      if  norm(gradz,inf) > 1E-4 % Check the First Order Opt. condition
          b =  - gradz;
          z = Q\b;  % z is the Newton direction      

          clear Q; % Release memory

          %stepsize = 1; % The default stepsize is 1
          obj1 =  objf(A, B, d, w0, b0, nu);      
          w2 = w0 + z(1:n); 
          b2 = b0 + z(n+1);
          obj2 = objf(A, B, d, w2, b2, nu);      

          if (obj1 - obj2) <= 1E-8
              % Use the Armijo's rule           
              gap = z'*gradz; % Compute the gap       
              % Find the step size & Update to the new point
              stepsize = armijo(A, B, d, w0, b0, nu, z, gap, obj1);
              w0 = w0 + stepsize*z(1:n);
              b0 = b0 + stepsize*z(n+1);              
          else
              % Use the Newton method
              w0 = w2;
              b0 = b2;    
          end 

          flag = norm(z,inf); 
      else      
          break;
      end
    end
    w = w0; b = b0;
    % out = struct('w',w,'b',b);
end

function stepsize = armijo(A, B, d, w, b, nu, zd, gap, obj1)
    % Input
    %   C = [A; -B]; equals "DA" in SSVM paper
    %   d: equals "De" in SSVM paper (i.e. the diagonal of "D")
    %   w1, b1: Current point
    %   nu: weight parameter 
    %   gap: defined in ssvm code
    %   obj1: the object function value of current point 
    %   diff: the difference between current point and the next point 
    % Note:
    %   You will need objf function to evaluate the objective function value.

    diff=0;
    temp=0.5; % we start to test with setpsize=0.5
    n = length(w);

    while diff  < -0.05*temp*gap
        temp = 0.5*temp;
        w2 = w + temp*zd(1:n); 
        b2 = b + temp*zd(n+1);
        obj2 = objf(A, B, d, w2, b2, nu);
        diff = obj1 - obj2;      
    end

    stepsize = temp;
end

function value = objf(A, B, d, w, b, nu)
    % Evaluate the function value
    wa=A*w; wb=-B*w;
    temp=abs(d)-([wa;wb]-b*d); % temp = abs(d)-(C*w - b*d);
    v = max(temp,0);
    value = 0.5*(v'*v + (1/nu)*(w'*w + b^2));
end
