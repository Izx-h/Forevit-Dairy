import * as React from "react";
import { cn } from "@/lib/utils";

export const Input = React.forwardRef<HTMLInputElement, React.InputHTMLAttributes<HTMLInputElement>>(
  ({ className, type = "text", ...props }, ref) => (
    <input
      ref={ref}
      type={type}
      className={cn("flex h-10 w-full rounded-xl border border-line bg-white px-3.5 py-2 text-sm text-ink shadow-sm transition placeholder:text-muted/70 focus-visible:border-pine-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-pine-100 disabled:cursor-not-allowed disabled:opacity-50", className)}
      {...props}
    />
  )
);
Input.displayName = "Input";

export const Textarea = React.forwardRef<HTMLTextAreaElement, React.TextareaHTMLAttributes<HTMLTextAreaElement>>(
  ({ className, ...props }, ref) => (
    <textarea
      ref={ref}
      className={cn("flex min-h-28 w-full resize-y rounded-xl border border-line bg-white px-3.5 py-3 text-sm leading-6 text-ink shadow-sm transition placeholder:text-muted/70 focus-visible:border-pine-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-pine-100 disabled:cursor-not-allowed disabled:opacity-50", className)}
      {...props}
    />
  )
);
Textarea.displayName = "Textarea";
