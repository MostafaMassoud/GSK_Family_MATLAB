function [x, f, current_eval] = egsk_ip_refine(bestx, f, current_eval, problem, Max_FES)
%EGSK_IP_REFINE Faithful port of the eGSK IP local refinement (fmincon SQP).
%
% Source (transcribed verbatim):
%   historical source: egsk/egsk/finaleGSK2023/IP.m
%
% Reference signature:
%   [x,f,current_eval,g,run_funcvals] = IP(bestx,f,current_eval,I_fno, ...
%                                          Max_FES,xmin,xmax,g,run_funcvals)
% The g and run_funcvals arguments are pure pass-throughs in IP.m (returned
% unmodified) and are dropped here. The hard-coded objective
% fmincon(@cec17_func, bestx(1,:)', ..., I_fno) is adapted to the generic
% problem interface: the column iterate is evaluated through
% problem.evaluate on its row form (the only adaptation, per the porting
% contract). Bounds are passed as problem.lb/problem.ub (the reference
% passes the row vectors lu(1,:)/lu(2,:) with a column x0; fmincon accepts
% either orientation).
%
% The caller guards Optimization Toolbox availability; this function
% assumes fmincon exists. The legacy optimset settings (including
% 'UseParallel','never') are kept exactly as the reference and verified to
% work with fmincon on R2025b.

IP_FE = ceil(2.0000e-003 * Max_FES); %% Max FFEs
options = optimset('Display', 'off', 'algorithm', 'sqp', ...
    'UseParallel', 'never', 'MaxFunEvals', IP_FE);

objective = @(z) problem.evaluate(z(:).'); % column iterate -> 1xD row -> scalar fitness

[Xsqp, FUN, ~, details] = fmincon(objective, bestx(1, :)', [], [], [], [], problem.lb, problem.ub, [], options);

%% check if there is an improvement in the fitness value and update
if (f - FUN) > 0
    f = FUN;
    x = bestx;
    x(1, :) = Xsqp; % reference assigns the column Xsqp into the row x(1,:)
else
    x = bestx;
end
%% update nfes
current_eval = current_eval + details.funcCount;
end
